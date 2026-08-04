# frozen_string_literal: true

class CreateTradingStrategies < ActiveRecord::Migration[8.0]
  def change
    create_table :trading_strategies do |t|
      t.string :name, null: false
      t.string :version, default: "1.0.0"
      t.string :status, default: "draft"
      t.text :code, default: ""
      t.text :description
      t.string :author, default: "System"
      t.string :runtime, default: "Ruby"
      t.string :timeframe, default: "1m"
      t.string :trade_direction, default: "both"
      t.jsonb :parameters, default: []
      t.jsonb :instruments, default: []
      t.jsonb :tags, default: []
      t.jsonb :checks, default: { syntax: "not_run", logic: "not_run", risk: "not_run", backtest: "not_run" }
      t.jsonb :backtest_results, default: {}

      t.timestamps
    end

    add_index :trading_strategies, :name
    add_index :trading_strategies, :status
    add_index :trading_strategies, %i[name version], unique: true
  end
end
