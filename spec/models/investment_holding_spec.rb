# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentHolding do
  subject(:holding) { build(:investment_holding) }

  it { is_expected.to belong_to(:investment_portfolio) }
  it { is_expected.to belong_to(:instrument) }
  it { is_expected.to have_many(:investment_lots).inverse_of(:investment_holding) }

  it "is unique per (portfolio, instrument)" do
    holding.save!
    dup = build(:investment_holding,
                investment_portfolio: holding.investment_portfolio,
                instrument: holding.instrument)
    expect(dup).not_to be_valid
    expect(dup.errors[:instrument]).to be_present
  end

  it "requires sleeve_key" do
    holding.sleeve_key = ""
    expect(holding).not_to be_valid
  end

  it "rejects negative quantities" do
    holding.quantity = -1
    expect(holding).not_to be_valid
  end

  it "enforces quantity = available_quantity + t1_quantity" do
    holding.quantity = 100
    holding.available_quantity = 90
    holding.t1_quantity = 5
    expect(holding).not_to be_valid
    expect(holding.errors[:available_quantity].join).to include("quantity - t1_quantity")
  end

  it "accepts a consistent T+1 split" do
    holding.quantity = 110
    holding.available_quantity = 100
    holding.t1_quantity = 10
    expect(holding).to be_valid
  end

  describe "#value_at" do
    it "multiplies quantity by the supplied price with BigDecimal precision" do
      holding.quantity = 3
      expect(holding.value_at(BigDecimal("333.33"))).to eq(BigDecimal("999.99"))
    end
  end
end
