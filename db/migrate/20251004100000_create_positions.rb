class CreatePositions < ActiveRecord::Migration[8.0]
  def change
    create_table :positions do |t|
      t.string :position_key, null: false
      t.string :order_no
      t.string :dhan_client_id
      t.string :trading_symbol
      t.string :security_id, null: false
      t.string :position_type
      t.string :exchange_segment
      t.string :product_type
      t.decimal :buy_avg, precision: 18, scale: 6
      t.integer :buy_qty
      t.decimal :cost_price, precision: 18, scale: 6
      t.decimal :sell_avg, precision: 18, scale: 6
      t.integer :sell_qty
      t.integer :net_qty
      t.decimal :realized_profit, precision: 18, scale: 6
      t.decimal :unrealized_profit, precision: 18, scale: 6
      t.decimal :rbi_reference_rate, precision: 18, scale: 6
      t.integer :multiplier
      t.integer :carry_forward_buy_qty
      t.integer :carry_forward_sell_qty
      t.decimal :carry_forward_buy_value, precision: 18, scale: 6
      t.decimal :carry_forward_sell_value, precision: 18, scale: 6
      t.integer :day_buy_qty
      t.integer :day_sell_qty
      t.decimal :day_buy_value, precision: 18, scale: 6
      t.decimal :day_sell_value, precision: 18, scale: 6
      t.date :drv_expiry_date
      t.string :drv_option_type
      t.decimal :drv_strike_price, precision: 18, scale: 6
      t.boolean :cross_currency
      t.datetime :closed_at
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :positions, :position_key, unique: true
    add_index :positions, :security_id
    add_index :positions, :order_no
  end
end
