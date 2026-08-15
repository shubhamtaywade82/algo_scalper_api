# frozen_string_literal: true

class CreateTradeJournals < ActiveRecord::Migration[8.1]
  def change
    create_table :trade_journals do |t|
      t.references :position_tracker, null: false, foreign_key: true
      t.references :instrument, null: false, foreign_key: true
      t.string :strategy_name
      t.string :side, null: false
      t.integer :quantity, null: false
      t.decimal :entry_price, precision: 12, scale: 4, null: false
      t.decimal :exit_price, precision: 12, scale: 4
      t.datetime :entry_time, null: false
      t.datetime :exit_time
      t.integer :hold_duration_seconds
      t.decimal :gross_pnl, precision: 12, scale: 4
      t.decimal :fees, precision: 12, scale: 4
      t.decimal :net_pnl, precision: 12, scale: 4
      t.decimal :pnl_percent, precision: 8, scale: 4
      t.decimal :max_favorable_excursion, precision: 12, scale: 4
      t.decimal :max_adverse_excursion, precision: 12, scale: 4
      t.string :exit_reason
      t.string :market_regime
      t.text :notes
      t.jsonb :entry_context, default: {}
      t.jsonb :exit_context, default: {}
      t.jsonb :meta, default: {}
      t.boolean :paper, default: false, null: false
      t.timestamps
    end

    add_index :trade_journals, :strategy_name
    add_index :trade_journals, :paper
    add_index :trade_journals, :created_at
    add_index :trade_journals, [:paper, :created_at]
  end
end
