# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentPortfolio do
  it "requires a unique name" do
    described_class.create!(name: "unique-portfolio", mode: "paper")
    dup = described_class.new(name: "unique-portfolio", mode: "paper")
    expect(dup).not_to be_valid
    expect(dup.errors[:name]).to be_present
  end

  it "rejects an unknown mode" do
    portfolio = described_class.new(name: "p2", mode: "crazy")
    expect(portfolio).not_to be_valid
  end

  it "blocks live mode without the Phase-4 env gate" do
    portfolio = described_class.new(name: "p3", mode: "live")
    expect(portfolio).not_to be_valid
    expect(portfolio.errors[:mode].join).to include("INVESTING_LIVE_CONFIRMED")
  end

  it "rejects negative cash" do
    portfolio = described_class.new(name: "p4", mode: "paper", cash_balance: -1)
    expect(portfolio).not_to be_valid
  end

  describe "#active_policy" do
    it "returns the active policy and not drafts" do
      portfolio = described_class.create!(name: "p5", mode: "paper")
      draft = InvestmentPolicy.create!(
        investment_portfolio: portfolio, mandate_version: "balanced_v1",
        status: "draft", rebalance_band_min_pct: 50, rebalance_band_max_pct: 60
      )
      expect(portfolio.active_policy).to be_nil
      expect(draft.status).to eq("draft")
    end
  end

  describe "#execution_paused?" do
    it "reads the meta flag safely" do
      portfolio = described_class.create!(name: "p6", mode: "paper")
      expect(portfolio.execution_paused?).to be(false)
      portfolio.update!(meta: { "execution_paused" => true })
      expect(portfolio.reload.execution_paused?).to be(true)
    end
  end
end
