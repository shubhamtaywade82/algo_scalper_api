# frozen_string_literal: true

# TDD §16 A1.4 / A1.7 — Valuer arithmetic: total = Σ holdings + cash,
# stale-price rule, caller-supplied price preference, cash-as-sleeve
# attribution, zero-holdings edge, boundary rounding.
require "rails_helper"

RSpec.describe Investing::Portfolios::Valuer do
  subject(:valuer) { described_class.new }

  def build_portfolio_with_holdings(cash:, holdings: [], prices: nil)
    portfolio = create(:investment_portfolio, cash_balance: cash)
    holdings.each do |attrs|
      instrument = create(:equity_instrument)
      create(:investment_holding,
             investment_portfolio: portfolio, instrument: instrument, **attrs)
    end
    [portfolio, valuer.valuation(portfolio, prices: prices)]
  end

  describe "#valuation" do
    it "values an empty portfolio to cash_balance (A1.4 zero-holdings edge)" do
      _portfolio, valuation = build_portfolio_with_holdings(cash: 77_777)
      expect(valuation.total_value).to eq(77_777)
      expect(valuation.invested_value).to be_zero
      expect(valuation.cost_basis).to be_zero
      expect(valuation.unrealized_pnl).to be_zero
      expect(valuation.sleeve_weights).to eq({ "cash" => BigDecimal("100.00") })
    end

    it "computes total = Σ(quantity × price) + cash with hand-checkable numbers" do
      _portfolio, valuation = build_portfolio_with_holdings(
        cash: 20_000,
        holdings: [
          { quantity: 100, last_price: 1600, average_cost_price: 1500, sleeve_key: "large_cap_core" },
          { quantity: 50, last_price: 800, average_cost_price: 700, sleeve_key: "mid_small_cap" }
        ]
      )
      # invested = 100*1600 + 50*800 = 200_000 ; total = 220_000
      expect(valuation.invested_value).to eq(200_000)
      expect(valuation.total_value).to eq(220_000)
      expect(valuation.cost_basis).to eq(185_000) # 100*1500 + 50*700
      expect(valuation.unrealized_pnl).to eq(15_000)
      expect(valuation.holding_values.values.sum).to eq(200_000)
    end

    it "falls back to the holding's stored last_price when no price supplied (stale rule)" do
      _portfolio, valuation = build_portfolio_with_holdings(
        cash: 0,
        holdings: [{ quantity: 10, last_price: 250.5, average_cost_price: 200, sleeve_key: "infra" }]
      )
      expect(valuation.invested_value).to eq(BigDecimal("2505.00"))
    end

    it "prefers a caller-supplied price over the stale stored one" do
      portfolio = create(:investment_portfolio, cash_balance: 0)
      holding = create(:investment_holding, investment_portfolio: portfolio,
                                            quantity: 10, last_price: 250.5)
      valuation = valuer.valuation(portfolio, prices: { holding.instrument_id => "999.99" })
      expect(valuation.invested_value).to eq(BigDecimal("9999.90"))
    end

    context "cash-as-sleeve (A1.7)" do
      it "attributes uninvested money to the cash sleeve, not spread across sleeves" do
        _portfolio, valuation = build_portfolio_with_holdings(
          cash: 60_000,
          holdings: [{ quantity: 100, last_price: 1000, average_cost_price: 1000, sleeve_key: "large_cap_core" }]
        )
        # total = 160_000 → large_cap 100_000/160_000 = 62.5%, cash 37.5%
        expect(valuation.sleeve_weights["large_cap_core"]).to eq(BigDecimal("62.50"))
        expect(valuation.sleeve_weights["cash"]).to eq(BigDecimal("37.50"))
        expect(valuation.sleeve_weights.values.sum).to eq(100)
      end

      it "rounds weights half-up to 2dp only at the boundary" do
        _portfolio, valuation = build_portfolio_with_holdings(
          cash: 1,
          holdings: [{ quantity: 3, last_price: 1, average_cost_price: 1, sleeve_key: "gold_silver" }]
        )
        # total 4 → 75.00 / 25.00 exactly representable at 2dp
        expect(valuation.sleeve_weights["gold_silver"]).to eq(BigDecimal("75.00"))
        expect(valuation.sleeve_weights["cash"]).to eq(BigDecimal("25.00"))

        _p2, v2 = build_portfolio_with_holdings(
          cash: 1,
          holdings: [{ quantity: 1, last_price: 1, average_cost_price: 1, sleeve_key: "gold_silver" }]
        )
        # total 2 → 50.00 / 50.00
        expect(v2.sleeve_weights["gold_silver"]).to eq(BigDecimal("50.00"))
        expect(v2.sleeve_weights["cash"]).to eq(BigDecimal("50.00"))
      end
    end

    it "groups multiple holdings of the same sleeve into one sleeve value" do
      _portfolio, valuation = build_portfolio_with_holdings(
        cash: 0,
        holdings: [
          { quantity: 10, last_price: 100, average_cost_price: 100, sleeve_key: "govt_aaa_bonds" },
          { quantity: 20, last_price: 100, average_cost_price: 100, sleeve_key: "govt_aaa_bonds" }
        ]
      )
      expect(valuation.sleeve_values["govt_aaa_bonds"]).to eq(3000)
      expect(valuation.sleeve_weights["govt_aaa_bonds"]).to eq(100)
    end

    it "omits a zero-cash row from sleeve_weights when fully invested" do
      _portfolio, valuation = build_portfolio_with_holdings(
        cash: 0,
        holdings: [{ quantity: 10, last_price: 100, average_cost_price: 100, sleeve_key: "infra" }]
      )
      expect(valuation.sleeve_weights).not_to have_key("cash")
      expect(valuation.sleeve_weights.keys).to eq(["infra"])
    end

    it "is a frozen immutable struct" do
      _portfolio, valuation = build_portfolio_with_holdings(cash: 5)
      expect(valuation).to be_frozen
      expect(valuation.sleeve_weights).to be_frozen
      expect(valuation.sleeve_values).to be_frozen
    end
  end
end
