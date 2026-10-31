# frozen_string_literal: true

# Investing domain: aggregated per-instrument exposure (TDD §4.3).
#
# quantity/average_cost mirror the BROKER-reconciled view (Dhan reports
# aggregates); investment_lots (Phase 3) are our own tax-lot accounting truth.
# Holdings are never deleted — fully-sold positions are zeroed and kept for
# audit (TDD §3.3 D3, A-SYNC-02).
class CreateInvestmentHoldings < ActiveRecord::Migration[8.1]
  def change
    create_table :investment_holdings do |t|
      t.references :investment_portfolio,
                   null: false, foreign_key: { on_delete: :cascade }
      t.references :instrument, type: :integer,
                                null: false, foreign_key: { on_delete: :restrict }
      t.string :sleeve_key, limit: 64
      t.string :source, null: false, default: "manual"
      t.decimal :quantity, precision: 20, scale: 4, null: false, default: 0
      t.decimal :average_cost, precision: 15, scale: 4
      t.decimal :last_price, precision: 15, scale: 4
      t.datetime :last_valued_at
      t.boolean :externally_held, null: false, default: false
      t.jsonb :broker_raw, null: false, default: {}
      t.datetime :synced_at
      t.timestamps
    end

    add_index :investment_holdings,
              %i[investment_portfolio_id instrument_id], unique: true
    add_index :investment_holdings, :sleeve_key
    add_index :investment_holdings, :source
    add_check_constraint :investment_holdings, "quantity >= 0",
                         name: "chk_inv_holdings_nonneg_quantity"
  end
end
