# frozen_string_literal: true

# Investing domain: portfolio identity (see docs/investing/TECHNICAL_DESIGN.md §4.2).
#
# One row per investment portfolio. The Trading domain's PositionTracker is NOT
# reused here: a trading position lives minutes, an investment holding lives
# years — different lifecycles, different tables (TDD §2, hard boundary #3).
#
# broker_linkage:
#   dhan    — linked to the Dhan demat account (at most one per dhan client id)
#   manual  — tracked in-app, orders planned but executed outside
#   external — record-keeping only (e.g. mutual funds outside the broker)
class CreateInvestmentPortfolios < ActiveRecord::Migration[8.1]
  def change
    create_table :investment_portfolios do |t|
      t.string :name, null: false
      t.string :base_currency, null: false, default: "INR", limit: 3
      t.integer :investment_horizon_years, null: false, default: 10
      t.string :risk_profile, null: false, default: "balanced"
      t.string :status, null: false, default: "active"
      t.string :broker_linkage, null: false, default: "manual"
      t.jsonb :external_ref, null: false, default: {}
      t.datetime :archived_at
      t.timestamps
    end

    add_index :investment_portfolios, :name, unique: true
    add_index :investment_portfolios, :status
    add_index :investment_portfolios, :broker_linkage
    # One Dhan-linked portfolio per broker client id (TDD §3.3 D6)
    add_index :investment_portfolios, "((external_ref->>'dhan_client_id'))",
              name: "idx_inv_portfolios_on_dhan_client_id", unique: true,
              where: "broker_linkage = 'dhan'"
  end
end
