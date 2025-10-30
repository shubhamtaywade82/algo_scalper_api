# frozen_string_literal: true

class CreatePaperTrade < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_trades do |t|
      t.references :paper_position, null: false, foreign_key: true
      t.references :paper_order, null: false, foreign_key: true
      t.decimal :entry_price, precision: 15, scale: 2, null: false
      t.decimal :exit_price, precision: 15, scale: 2, null: false
      t.decimal :pnl_rupees, precision: 15, scale: 2, default: 0
      t.decimal :pnl_percent, precision: 10, scale: 4, default: 0
      t.decimal :brokerage, precision: 10, scale: 2, default: 0
      t.decimal :net_pnl, precision: 15, scale: 2, default: 0
      t.datetime :entry_time
      t.datetime :exit_time
      t.integer :duration_seconds
      t.string :signal_source

      t.timestamps
    end
  end
end
