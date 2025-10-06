class CreateTradeLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :trade_logs do |t|
      t.string :strategy, null: false
      t.string :symbol
      t.string :segment, null: false
      t.string :security_id, null: false
      t.integer :direction, null: false
      t.integer :status, null: false, default: 0
      t.integer :quantity, null: false
      t.decimal :entry_price, precision: 15, scale: 4
      t.decimal :stop_price, precision: 15, scale: 4
      t.decimal :target_price, precision: 15, scale: 4
      t.decimal :risk_amount, precision: 15, scale: 4
      t.decimal :estimated_profit, precision: 15, scale: 4
      t.string :order_id
      t.datetime :placed_at
      t.string :exit_order_id
      t.decimal :exit_price, precision: 15, scale: 4
      t.datetime :closed_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :trade_logs, :strategy
    add_index :trade_logs, [:strategy, :security_id, :status], name: "index_trade_logs_on_strategy_security_status"
  end
end
