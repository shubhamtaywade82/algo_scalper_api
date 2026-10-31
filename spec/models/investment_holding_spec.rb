# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentHolding do
  describe "associations" do
    it { is_expected.to belong_to(:investment_portfolio) }
    it { is_expected.to belong_to(:instrument) }
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:source).in_array(%w[dhan_sync manual external]) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to allow_value("indian_large_cap").for(:sleeve_key) }
    it { is_expected.to allow_value(nil).for(:sleeve_key) }
    it { is_expected.not_to allow_value("Bad Key").for(:sleeve_key) }
  end

  describe "uniqueness of instrument per portfolio" do
    it "rejects a second holding for the same instrument" do
      holding = create(:investment_holding)
      duplicate = build(:investment_holding, investment_portfolio: holding.investment_portfolio,
                                             instrument: holding.instrument)

      expect(duplicate).not_to be_valid
    end
  end

  describe "scopes" do
    it "separates held, unclassified and broker-synced holdings" do
      portfolio = create(:investment_portfolio)
      sold_out = create(:investment_holding, investment_portfolio: portfolio, quantity: 0)
      unclassified = create(:investment_holding, investment_portfolio: portfolio, sleeve_key: nil)
      synced = create(:investment_holding, :dhan_synced, investment_portfolio: portfolio)

      expect(portfolio.holdings.held).not_to include(sold_out)
      expect(portfolio.holdings.unclassified).to contain_exactly(unclassified)
      expect(portfolio.holdings.broker_synced).to contain_exactly(synced)
    end
  end

  describe "#market_value" do
    it "multiplies quantity by the last price" do
      holding = build(:investment_holding, quantity: BigDecimal("10.5"),
                                           last_price: BigDecimal("250"))

      expect(holding.market_value).to eq(BigDecimal("2625.0"))
    end

    it "returns nil when never valued" do
      expect(build(:investment_holding, last_price: nil).market_value).to be_nil
    end
  end
end
