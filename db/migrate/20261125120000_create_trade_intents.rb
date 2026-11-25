# frozen_string_literal: true

class CreateTradeIntents < ActiveRecord::Migration[8.1]
  def change
    create_table :trade_intents do |t|
      t.uuid :intent_id, null: false
      t.string :mode, null: false
      t.string :underlying, null: false
      t.string :direction, null: false
      t.string :source_strategy, null: false
      t.decimal :confidence, precision: 5, scale: 4, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :expires_at, null: false
      t.string :outcome
      t.string :outcome_code
      t.string :outcome_detail
      t.string :correlation_id
      t.datetime :decided_at
      t.references :strategy_signal, foreign_key: { to_table: :strategy_signals }, null: true
      t.timestamps

      t.index :intent_id, unique: true
      t.index %i[mode outcome expires_at]
      t.index %i[underlying direction expires_at]
    end
  end
end
