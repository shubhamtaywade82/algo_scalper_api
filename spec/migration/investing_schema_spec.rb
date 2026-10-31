# frozen_string_literal: true

# TDD §16 A1.1 — the investing migration set applies cleanly UP *and* DOWN:
# migrate -> assert tables/indexes -> roll back -> assert absent -> re-apply
# so the test DB is left in the loaded state for later examples.
require "rails_helper"
# Migration classes are NOT autoloaded — load the file directly.
require_relative "../../db/migrate/20261031080000_create_investment_tables"

RSpec.describe "investing schema (CreateInvestmentTables)" do
  INVESTING_TABLES = %w[
    investment_portfolios
    investment_policies
    allocation_sleeves
    investment_holdings
    investment_rebalances
    investment_orders
    investment_lots
    investment_fills
    investment_transactions
    investment_snapshots
  ].freeze

  def connection
    ActiveRecord::Base.connection
  end

  def run_migration(direction)
    CreateInvestmentTables.new.migrate(direction)
  end

  it "applies cleanly up and down on a fresh DB" do
    expect(INVESTING_TABLES.all? { |t| connection.table_exists?(t) }).to be(true)

    run_migration(:down)
    expect(INVESTING_TABLES.none? { |t| connection.table_exists?(t) }).to be(true)

    run_migration(:up)
    expect(INVESTING_TABLES.all? { |t| connection.table_exists?(t) }).to be(true)
  end

  it "carries the safety-critical unique indexes after a full down/up cycle" do
    run_migration(:down)
    run_migration(:up)

    # idempotency backbone (TDD §12.5): correlation ids unique
    expect(connection.index_exists?(:investment_orders, :correlation_id, unique: true)).to be(true)
    # fill ingestion idempotency: one row per broker trade id
    expect(connection.index_exists?(:investment_fills, :broker_trade_id, unique: true)).to be(true)
    # one active policy per portfolio (partial unique index)
    idx = connection.indexes(:investment_policies)
                 .find { |i| i.unique && i.columns.include?("investment_portfolio_id") }
    expect(idx).not_to be_nil, "expected a partial unique index enforcing one active policy"
    # snapshot idempotency: one per (portfolio, as_of_date)
    expect(connection.index_exists?(:investment_snapshots,
                                    %i[investment_portfolio_id as_of_date], unique: true)).to be(true)
    # FIFO scan support on lots
    expect(connection.index_exists?(:investment_lots,
                                    %i[investment_holding_id acquired_on])).to be(true)
  end

  it "keeps money columns at the documented precision" do
    run_migration(:down)
    run_migration(:up)

    money_columns = {
      %i[investment_transactions amount] => [18, 2],
      %i[investment_snapshots total_value] => [18, 2],
      %i[investment_holdings quantity] => [18, 4],
      %i[investment_lots buy_price] => [18, 4]
    }
    money_columns.each do |(table, column), (precision, scale)|
      col = connection.columns(table).find { |c| c.name == column.to_s }
      expect(col).not_to be_nil, "missing column #{table}.#{column}"
      expect([col.precision, col.scale]).to eq([precision, scale]),
                                            "wrong precision on #{table}.#{column}"
    end
  end
end
