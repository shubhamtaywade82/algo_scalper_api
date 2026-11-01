# frozen_string_literal: true

require "rails_helper"

# Duck-typed state/order builders — the spike runs before Order/Holding
# models exist (TDD §18). Field lists mirror the TDD §9.1 contract.
# Top-level (outside the describe block) so they are not leaked-constant
# offenses; namespaced to avoid cross-file collisions.
module InvestingPolicyValidatorSpec
  State = Struct.new(:cash_balance, :holdings, :orders_today, keyword_init: true)
  Holding = Struct.new(:instrument_id, :sleeve_key, :asset_class, :sector, :value,
                       :is_illiquid, keyword_init: true)
  Order = Struct.new(:side, :instrument_id, :sleeve_key, :asset_class, :sector,
                     :value, :quantity, :available_quantity, :is_illiquid,
                     keyword_init: true)
end

RSpec.describe Investing::Risk::PolicyValidator do
  subject(:validator) { described_class.new }

  def state(cash:, holdings: [], orders_today: 0)
    InvestingPolicyValidatorSpec::State.new(cash_balance: cash, holdings: holdings, orders_today: orders_today)
  end

  def order(side:, value:, instrument_id: 99, asset_class: "debt", sector: "Fresh",
            quantity: nil, available_quantity: nil, is_illiquid: false)
    InvestingPolicyValidatorSpec::Order.new(side: side, instrument_id: instrument_id, sleeve_key: "x",
                                            asset_class: asset_class, sector: sector, value: value,
                                            quantity: quantity || (value / 100.0), available_quantity: available_quantity || 1_000_000,
                                            is_illiquid: is_illiquid)
  end

  describe "#check" do
    it "accepts a clean small buy" do
      result = validator.check(portfolio_state: state(cash: 100_000),
                               order: order(side: :buy, value: 1_000))
      expect(result).to be_ok
      expect(result.violations).to be_empty
    end

    describe "max_single_stock (2.5% cap)" do
      it "blocks when post-trade weight exceeds the cap" do
        # 2_501 / (97_500 + 2_501) = 2.5010% > 2.5
        result = validator.check(portfolio_state: state(cash: 97_500),
                                 order: order(side: :buy, value: 2_501))
        expect(result).not_to be_ok
        expect(result.violations.map(&:rule)).to include(:max_single_stock)
      end

      it "passes at exactly the cap" do
        # 2_500 / 100_000 = 2.50%
        result = validator.check(portfolio_state: state(cash: 97_500),
                                 order: order(side: :buy, value: 2_500))
        expect(result).to be_ok
      end
    end

    describe "max_sector (12% cap)" do
      let(:holdings) do
        [InvestingPolicyValidatorSpec::Holding.new(instrument_id: 1, sleeve_key: "infra", asset_class: "equity",
                                                   sector: "Energy", value: 11_000, is_illiquid: false)]
      end

      it "blocks when post-trade sector weight exceeds the cap" do
        # (11_000 + 1_300) / (99_000 + 1_300) = 12.26% > 12
        result = validator.check(portfolio_state: state(cash: 88_000, holdings: holdings),
                                 order: order(side: :buy, value: 1_300, sector: "Energy"))
        expect(result.violations.map(&:rule)).to include(:max_sector)
      end

      it "passes at exactly the cap" do
        # (11_000 + 1_000) / (99_000 + 1_000) = 12.00%
        result = validator.check(portfolio_state: state(cash: 88_000, holdings: holdings),
                                 order: order(side: :buy, value: 1_000, sector: "Energy"))
        expect(result).to be_ok
      end
    end

    describe "max_illiquid (25% cap)" do
      let(:holdings) do
        [InvestingPolicyValidatorSpec::Holding.new(instrument_id: 1, sleeve_key: "short_duration_debt",
                                                   asset_class: "debt", sector: "SME", value: 24_000, is_illiquid: true)]
      end

      it "blocks when post-trade illiquid weight exceeds the cap" do
        # (24_000 + 2_000) / (99_000 + 2_000) = 25.74% > 25
        result = validator.check(portfolio_state: state(cash: 75_000, holdings: holdings),
                                 order: order(side: :buy, value: 2_000, is_illiquid: true))
        expect(result.violations.map(&:rule)).to include(:max_illiquid)
      end

      it "passes at exactly the cap" do
        # (24_000 + 1_000) / (99_000 + 1_000) = 25.00%
        result = validator.check(portfolio_state: state(cash: 75_000, holdings: holdings),
                                 order: order(side: :buy, value: 1_000, is_illiquid: true))
        expect(result).to be_ok
      end
    end

    describe "equity_band (symmetric 50-60 guard)" do
      # 25 equity holdings @ 2_024 = 50_600 equity, cash 49_400, total 100_000
      def equity_state(holding_value:, count:, cash:)
        holdings = Array.new(count) do |i|
          InvestingPolicyValidatorSpec::Holding.new(instrument_id: i + 1, sleeve_key: "large_cap_core",
                                                    asset_class: "equity", sector: "Sector#{i}", value: holding_value,
                                                    is_illiquid: false)
        end
        state(cash: cash, holdings: holdings)
      end

      it "blocks an equity buy that pushes weight above the band max" do
        # 30 × 1_980 = 59_400 equity, cash 40_000, total 99_400
        # (59_400 + 601) / (99_400 + 601) = 60.0001% > 60
        st = equity_state(holding_value: 1_980, count: 30, cash: 40_000)
        result = validator.check(portfolio_state: st,
                                 order: order(side: :buy, value: 601, asset_class: "equity"))
        expect(result.violations.map(&:rule)).to include(:equity_band)
      end

      it "passes an equity buy landing exactly at the band max" do
        # (59_400 + 600) / (99_400 + 600) = 60.0000%
        st = equity_state(holding_value: 1_980, count: 30, cash: 40_000)
        result = validator.check(portfolio_state: st,
                                 order: order(side: :buy, value: 600, asset_class: "equity"))
        expect(result).to be_ok
      end

      it "blocks an equity sell that pushes weight below the band min" do
        # 25 × 2_024 = 50_600 equity, cash 49_400, total 100_000
        # sell 1_201 → 49_399/98_799 = 49.999% < 50
        st = equity_state(holding_value: 2_024, count: 25, cash: 49_400)
        result = validator.check(portfolio_state: st,
                                 order: order(side: :sell, value: 1_201, asset_class: "equity",
                                              instrument_id: 1, quantity: 12, available_quantity: 100))
        expect(result.violations.map(&:rule)).to include(:equity_band)
      end

      it "passes an equity sell landing exactly at the band min" do
        # sell 1_200 → 49_400/98_800 = 50.000%
        st = equity_state(holding_value: 2_024, count: 25, cash: 49_400)
        result = validator.check(portfolio_state: st,
                                 order: order(side: :sell, value: 1_200, asset_class: "equity",
                                              instrument_id: 1, quantity: 12, available_quantity: 100))
        expect(result).to be_ok
      end
    end

    describe "max_order_value (500k backstop)" do
      it "blocks an order above the ceiling" do
        result = validator.check(portfolio_state: state(cash: 1_000_000),
                                 order: order(side: :buy, value: 500_001))
        expect(result.violations.map(&:rule)).to include(:max_order_value)
      end

      it "passes at exactly the ceiling" do
        result = validator.check(portfolio_state: state(cash: 20_000_000),
                                 order: order(side: :buy, value: 500_000))
        expect(result).to be_ok
      end
    end

    describe "max_orders_per_day (12)" do
      it "blocks the 13th order" do
        result = validator.check(portfolio_state: state(cash: 1_000_000, orders_today: 12),
                                 order: order(side: :buy, value: 1_000))
        expect(result.violations.map(&:rule)).to include(:max_orders_per_day)
      end

      it "passes on the 12th order" do
        result = validator.check(portfolio_state: state(cash: 1_000_000, orders_today: 11),
                                 order: order(side: :buy, value: 1_000))
        expect(result).to be_ok
      end
    end

    describe "insufficient_available_qty (T+1 guard)" do
      let(:holdings) do
        [InvestingPolicyValidatorSpec::Holding.new(instrument_id: 7, sleeve_key: "govt_aaa_bonds", asset_class: "debt",
                                                   sector: "Bonds", value: 5_000, is_illiquid: false)]
      end

      it "blocks a sell above available quantity" do
        result = validator.check(portfolio_state: state(cash: 95_000, holdings: holdings),
                                 order: order(side: :sell, value: 5_000, instrument_id: 7,
                                              quantity: 101, available_quantity: 100))
        expect(result.violations.map(&:rule)).to include(:insufficient_available_qty)
      end

      it "passes a sell exactly equal to available quantity" do
        result = validator.check(portfolio_state: state(cash: 95_000, holdings: holdings),
                                 order: order(side: :sell, value: 5_000, instrument_id: 7,
                                              quantity: 100, available_quantity: 100))
        expect(result).to be_ok
      end
    end

    it "reports multiple violations together with details" do
      result = validator.check(portfolio_state: state(cash: 1_000_000, orders_today: 12),
                               order: order(side: :buy, value: 500_001))
      rules = result.violations.map(&:rule)
      expect(rules).to include(:max_order_value, :max_orders_per_day)
      violation = result.violations.find { |v| v.rule == :max_order_value }
      expect(violation.actual.to_s("F")).to eq("500001.0")
      expect(violation.limit.to_s("F")).to eq("500000.0")
      expect(violation.message).to include("exceeds")
    end

    it "raises ArgumentError on an unknown side" do
      expect do
        validator.check(portfolio_state: state(cash: 1_000),
                        order: order(side: :short, value: 100))
      end.to raise_error(ArgumentError, /side must be :buy or :sell/)
    end
  end
end
