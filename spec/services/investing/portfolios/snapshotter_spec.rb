# frozen_string_literal: true

# TDD §16 A1.8 — Snapshotter idempotent per (portfolio, date): re-running
# the same date overwrites, never duplicates; it is the ONLY writer of
# investment_snapshots and persists the Valuation's numbers verbatim.
require "rails_helper"

RSpec.describe Investing::Portfolios::Snapshotter do
  subject(:snapshotter) { described_class.new }

  let(:portfolio) { create(:investment_portfolio, cash_balance: 50_000) }
  let(:date) { Date.new(2026, 10, 31) }

  describe "#snapshot!" do
    it "creates a snapshot carrying the valuation numbers" do
      holding = create(:investment_holding, investment_portfolio: portfolio,
                                            quantity: 10, last_price: 1500,
                                            average_cost_price: 1400,
                                            sleeve_key: "large_cap_core")
      holding # instantiate
      snapshot = snapshotter.snapshot!(portfolio, date: date)

      expect(snapshot).to be_persisted
      expect(snapshot.as_of_date).to eq(date)
      # total = 10*1500 + 50_000 = 65_000
      expect(snapshot.total_value).to eq(65_000)
      expect(snapshot.cash_balance).to eq(50_000)
      expect(snapshot.invested_value).to eq(15_000)
      expect(snapshot.sleeve_weights).to include("large_cap_core", "cash")
    end

    it "is idempotent: re-running the same date overwrites, not duplicates (A1.8)" do
      first = snapshotter.snapshot!(portfolio, date: date)

      # market moves overnight (intraday re-run, same business date)
      portfolio.update!(cash_balance: 40_000)
      second = snapshotter.snapshot!(portfolio, date: date)

      expect(second.id).to eq(first.id)
      expect(portfolio.investment_snapshots.where(as_of_date: date).count).to eq(1)
      expect(second.reload.cash_balance).to eq(40_000)
      expect(second.total_value).to eq(40_000)
    end

    it "keeps distinct rows per distinct date" do
      snapshotter.snapshot!(portfolio, date: date)
      snapshotter.snapshot!(portfolio, date: date + 1)
      expect(portfolio.investment_snapshots.count).to eq(2)
    end

    it "defaults the date to the IST business date" do
      ist_today = Time.now.in_time_zone("Asia/Kolkata").to_date
      snapshot = snapshotter.snapshot!(portfolio)
      expect(snapshot.as_of_date).to eq(ist_today)
    end

    it "serializes sleeve_weights with string keys (jsonb-safe)" do
      create(:investment_holding, investment_portfolio: portfolio,
                                  sleeve_key: "gold_silver")
      snapshot = snapshotter.snapshot!(portfolio, date: date)
      expect(snapshot.sleeve_weights.keys).to all(be_a(String))
    end
  end
end
