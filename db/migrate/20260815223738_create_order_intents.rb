# frozen_string_literal: true

class CreateOrderIntents < ActiveRecord::Migration[8.1]
  def change
    create_table :order_intents do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :strategy_name, null: false
      t.string :side, null: false                          # BUY / SELL
      t.integer :quantity, null: false
      t.string :order_type, default: 'MARKET', null: false # MARKET / LIMIT / SL / SLM
      t.string :product_type, default: 'INTRADAY', null: false  # INTRADAY / CNC / MARGIN
      t.string :validity, default: 'DAY', null: false      # DAY / IOC
      t.decimal :limit_price, precision: 12, scale: 4
      t.decimal :trigger_price, precision: 12, scale: 4
      t.decimal :stop_loss, precision: 12, scale: 4
      t.decimal :target, precision: 12, scale: 4
      t.boolean :risk_approved, default: false, null: false
      t.boolean :margin_approved, default: false, null: false
      t.string :status, default: 'created', null: false
      t.string :correlation_id
      t.string :rejection_reason
      t.jsonb :meta, default: {}, null: false
      t.timestamps
    end

    add_index :order_intents, :correlation_id, unique: true, where: 'correlation_id IS NOT NULL'
    add_index :order_intents, :status
    add_index :order_intents, :strategy_name
    add_index :order_intents, [:instrument_id, :status]
  end
end
