# frozen_string_literal: true

# TDD §16 A1.10 — Creator refuses duplicate names, unknown mandates and
# live mode before Phase 4; happy path materializes policy + sleeves +
# opening deposit + audit event atomically.
require "rails_helper"

RSpec.describe Investing::Portfolios::Creator do
  subject(:creator) { described_class.new }

  describe "#call" do
    context "happy path" do
      it "creates a paper portfolio with an ACTIVE policy and all sleeves" do
        portfolio = creator.call(
          name: "core-book", mandate: "balanced_v1", initial_cash: 1_000_000
        )

        expect(portfolio).to be_persisted
        expect(portfolio.mode).to eq("paper")
        expect(portfolio.cash_balance).to eq(1_000_000)

        policy = portfolio.active_policy
        expect(policy).not_to be_nil
        expect(policy.status).to eq("active")
        expect(policy.mandate_version).to eq("balanced_v1")
        expect(policy.allocation_sleeves.count).to eq(10)
        # weights materialized from config, sum exactly 100 (§5.2)
        expect(policy.allocation_sleeves.sum(&:target_weight_pct)).to eq(100)
      end

      it "records the opening deposit transaction and one audit event" do
        expect {
          creator.call(name: "audited", mandate: "balanced_v1", initial_cash: 250_000)
        }.to change(InvestmentTransaction, :count).by(1)
          .and change(AuditLog.where(event_type: "investing_portfolio_created"), :count).by(1)

        deposit = InvestmentTransaction.order(:id).last
        expect(deposit.txn_type).to eq("deposit")
        expect(deposit.amount).to eq(250_000)
      end

      it "creates no deposit row when initial_cash is zero" do
        portfolio = creator.call(name: "empty", mandate: "balanced_v1", initial_cash: 0)
        expect(portfolio.cash_balance).to be_zero
        expect(portfolio.investment_transactions.count).to be_zero
      end

      it "materializes the mandate constraints onto the policy" do
        portfolio = creator.call(name: "constrained", mandate: "balanced_v1", initial_cash: 1)
        constraints = portfolio.active_policy.constraints
        expect(constraints["max_single_stock_pct"].to_f).to eq(2.5)
        expect(constraints).to have_key("max_sector_pct")
      end
    end

    context "rejections (A1.10)" do
      before { creator.call(name: "taken", mandate: "balanced_v1", initial_cash: 100) }

      it "refuses a duplicate portfolio name with a typed error" do
        expect {
          creator.call(name: "taken", mandate: "balanced_v1", initial_cash: 100)
        }.to raise_error(Investing::ValidationError, /name already taken/)
      end

      it "refuses an unknown mandate with a typed error" do
        expect {
          creator.call(name: "fresh", mandate: "aggressive_v9", initial_cash: 100)
        }.to raise_error(Investing::ValidationError, /unknown investing mandate/)
      end

      it "refuses negative initial cash" do
        expect {
          creator.call(name: "negative", mandate: "balanced_v1", initial_cash: -1)
        }.to raise_error(Investing::ValidationError, /initial_cash must be >= 0/)
      end

      it "refuses live mode while the Phase-4 gate is closed" do
        expect {
          creator.call(name: "live-too-early", mode: :live,
                       mandate: "balanced_v1", initial_cash: 100)
        }.to raise_error(Investing::ValidationError, /INVESTING_LIVE_CONFIRMED/)
      end
    end

    context "atomicity" do
      it "rolls back everything when sleeve materialization fails mid-way" do
        # Force a sleeve failure (blank key) after the portfolio row was created
        # inside the transaction — nothing may leak (§6.1 rule 1).
        config = instance_double(Investing::Config,
                                 mandate: { "description" => "test" },
                                 mandates: { "balanced_v1" => { "description" => "test" } },
                                 sleeves_for: [
                                   { "key" => "good", "name" => "ok", "asset_class" => "equity", "target_weight_pct" => 100 },
                                   { "key" => "", "name" => "bad", "asset_class" => "equity", "target_weight_pct" => 0 }
                                 ],
                                 constraints_for: { "max_single_stock_pct" => 2.5 },
                                 equity_band_for: [BigDecimal("50"), BigDecimal("60")])
        creator = described_class.new(config: config)
        expect {
          creator.call(name: "rolled-back", mandate: "balanced_v1", initial_cash: 5)
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(InvestmentPortfolio.exists?(name: "rolled-back")).to be(false)
        expect(AuditLog.where(event_type: "investing_portfolio_created").count).to eq(0)
      end
    end
  end
end
