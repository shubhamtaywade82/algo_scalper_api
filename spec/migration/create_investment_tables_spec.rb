# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261031080000_create_investment_tables").to_s

# TDD §4 / §16 A1.1 — the investing migration set applied cleanly (schema:load
# in CI + db:migrate locally both exercise it). These specs pin the tables and
# the safety-critical indexes so accidental schema drift fails fast.
RSpec.describe CreateInvestmentTables do
  let(:tables) do
    %w[
      investment_portfolios investment_policies allocation_sleeves
      investment_holdings investment_lots investment_orders investment_fills
      investment_transactions investment_snapshots investment_rebalances
    ]
  end

  delegate :connection, to: :'ActiveRecord::Base'

  it "creates all ten tables" do
    tables.each do |table|
      expect(connection.table_exists?(table)).to be(true), "missing table #{table}"
    end
  end

  describe "safety-critical indexes" do
    it "uniquely keys order correlation ids (idempotency backbone, §12.5)" do
      expect(connection.index_exists?(:investment_orders, :correlation_id, unique: true)).to be(true)
    end

    it "uniquely keys fills by broker trade id (idempotent fill ingestion)" do
      expect(connection.index_exists?(:investment_fills, :broker_trade_id, unique: true)).to be(true)
    end

    it "enforces one active policy per portfolio (partial unique index)" do
      expect(connection.index_exists?(:investment_policies, :investment_portfolio_id,
                                      unique: true,
                                      name: "idx_investment_policies_one_active_per_portfolio")).to be(true)
    end

    it "uniquely keys snapshots per portfolio per day" do
      expect(connection.index_exists?(:investment_snapshots,
                                      %i[investment_portfolio_id as_of_date], unique: true)).to be(true)
    end

    it "uniquely keys sleeves within a policy" do
      expect(connection.index_exists?(:allocation_sleeves,
                                      %i[investment_policy_id sleeve_key], unique: true)).to be(true)
    end

    it "uniquely keys holdings per portfolio per instrument" do
      expect(connection.index_exists?(:investment_holdings,
                                      %i[investment_portfolio_id instrument_id], unique: true)).to be(true)
    end
  end

  describe "column contracts" do
    it "gives money columns the documented precision" do
      cols = connection.columns(:investment_orders)
      qty = cols.find { |c| c.name == "quantity" }
      expect(qty.precision).to eq(18)
      expect(qty.scale).to eq(4)
      expect(qty.sql_type).to include("numeric")
    end

    it "defaults product_type to CNC" do
      col = connection.columns(:investment_orders).find { |c| c.name == "product_type" }
      expect(col.default).to eq("CNC")
    end

    it "stores sleeve weights and broker payloads as jsonb" do
      expect(connection.columns(:investment_rebalances)
             .find { |c| c.name == "drift_report" }.sql_type).to eq("jsonb")
    end
  end
end
