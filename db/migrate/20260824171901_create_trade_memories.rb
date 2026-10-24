# frozen_string_literal: true

class CreateTradeMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :trade_memories do |t|
      t.references :position_tracker, null: false, foreign_key: true
      t.references :trade_analytic, null: true, foreign_key: true
      t.string :symbol
      t.string :strategy_name
      t.string :regime_at_entry
      t.string :regime_at_exit
      t.decimal :entry_quality_score, precision: 5, scale: 2
      t.decimal :exit_efficiency_pct, precision: 6, scale: 2
      t.decimal :pnl_rupees, precision: 12, scale: 4
      t.string :exit_reason
      t.text :lesson, null: false
      t.string :category, null: false, default: 'general'
      t.decimal :confidence, precision: 3, scale: 2, default: 0.5
      t.timestamps
    end

    add_index :trade_memories, :symbol
    add_index :trade_memories, :category
    add_index :trade_memories, :strategy_name
    add_index :trade_memories, [:position_tracker_id], unique: true, name: 'index_trade_memories_on_tracker_uniq'
  end
end
