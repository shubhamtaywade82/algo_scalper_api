# frozen_string_literal: true

class AddDeployFieldsToTradingStrategies < ActiveRecord::Migration[8.0]
  def change
    add_column :trading_strategies, :slug, :string
    add_column :trading_strategies, :strategy_record_id, :bigint
    add_column :trading_strategies, :entry_rules, :jsonb, default: {}
    add_column :trading_strategies, :exit_rules, :jsonb, default: {}
    add_column :trading_strategies, :risk_management, :jsonb, default: {}
    add_column :trading_strategies, :filters, :jsonb, default: {}
    add_column :trading_strategies, :schedule, :jsonb, default: {}

    add_index :trading_strategies, :slug, unique: true
    add_index :trading_strategies, :strategy_record_id
  end
end
