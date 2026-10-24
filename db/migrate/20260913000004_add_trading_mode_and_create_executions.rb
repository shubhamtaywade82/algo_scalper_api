# frozen_string_literal: true

# Introduces the TradingMode concept and first-class Execution records.
#
# 1. `position_trackers.trading_mode` ('paper' | 'live')
#    The `paper` boolean stays as a synced compatibility mirror, but the
#    canonical discriminator is now an explicit mode — the same direction the
#    ledger (ledger_journal_entries.mode) and paper_daily_wallets (mode)
#    already took. No heavyweight multi-account machinery: this is a solo
#    single-user system with one paper and one live book.
#
# 2. `executions`
#    Both live and paper fills flow into the same Execution record
#    (order/fill/bid/ask/slippage/fees/source), so downstream position and
#    ledger code consumes one event shape regardless of gateway.
class AddTradingModeAndCreateExecutions < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:position_trackers, :trading_mode)
      add_column :position_trackers, :trading_mode, :string, default: 'live', null: false
    end
    execute 'UPDATE position_trackers SET trading_mode = \'paper\' WHERE paper = TRUE'

    return if table_exists?(:executions)

    create_table :executions do |t|
      t.references :instrument, type: :bigint, null: false, foreign_key: true
      t.references :position_tracker, type: :bigint, foreign_key: true
      t.string :order_no, null: false
      t.string :client_order_id
      t.string :side, null: false
      t.string :purpose, null: false, default: 'entry'
      t.string :source, null: false, default: 'paper'
      t.string :status, null: false, default: 'filled'
      t.integer :quantity, null: false
      t.decimal :requested_price, precision: 12, scale: 4
      t.decimal :fill_price, precision: 12, scale: 4
      t.decimal :bid, precision: 12, scale: 4
      t.decimal :ask, precision: 12, scale: 4
      t.decimal :slippage, precision: 12, scale: 4
      t.decimal :fees, precision: 12, scale: 4, default: 0
      t.datetime :filled_at
      t.jsonb :meta, default: {}
      t.timestamps
    end

    add_index :executions, :order_no
    add_index :executions, %i[position_tracker_id purpose]
    add_index :executions, %i[instrument_id filled_at]
    add_index :executions, %i[source status]
  end

  def down
    drop_table :executions if table_exists?(:executions)
    remove_column :position_trackers, :trading_mode if column_exists?(:position_trackers, :trading_mode)
  end
end
