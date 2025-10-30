# frozen_string_literal: true

class CreatePaperDailyWalletsAndFillsLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :paper_daily_wallets do |t|
      t.date    :trading_date, null: false
      t.decimal :opening_cash, precision: 18, scale: 2, null: false, default: 0
      t.decimal :closing_cash, precision: 18, scale: 2, null: false, default: 0
      t.decimal :gross_pnl,    precision: 18, scale: 2, null: false, default: 0
      t.decimal :fees_total,   precision: 18, scale: 2, null: false, default: 0
      t.decimal :net_pnl,      precision: 18, scale: 2, null: false, default: 0
      t.decimal :max_drawdown, precision: 18, scale: 2, null: false, default: 0
      t.decimal :max_equity,   precision: 18, scale: 2, null: false, default: 0
      t.decimal :min_equity,   precision: 18, scale: 2, null: false, default: 0
      t.integer :trades_count, null: false, default: 0
      t.jsonb   :meta,         null: false, default: {}
      t.timestamps
    end
    add_index :paper_daily_wallets, :trading_date, unique: true

    create_table :paper_fills_logs do |t|
      t.date    :trading_date, null: false
      t.string  :exchange_segment, null: false
      t.bigint  :security_id, null: false
      t.string  :side, null: false
      t.integer :qty, null: false
      t.decimal :price, precision: 12, scale: 2, null: false
      t.decimal :charge, precision: 10, scale: 2, null: false, default: 20
      t.decimal :gross_value, precision: 14, scale: 2, null: false
      t.decimal :net_value, precision: 14, scale: 2, null: false
      t.datetime :executed_at, null: false
      t.jsonb  :meta, null: false, default: {}
      t.timestamps
    end
    add_index :paper_fills_logs, [:trading_date, :exchange_segment, :security_id], name: 'index_paper_fills_on_date_seg_sid'
  end
end


