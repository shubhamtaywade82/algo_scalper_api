class CreateBrokerOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :broker_orders do |t|
      t.string :order_no, null: false
      t.string :exch_order_no
      t.string :status, null: false
      t.integer :quantity
      t.integer :traded_quantity
      t.decimal :price, precision: 15, scale: 6
      t.decimal :avg_traded_price, precision: 15, scale: 6
      t.decimal :trigger_price, precision: 15, scale: 6
      t.string :transaction_type
      t.string :order_type
      t.string :product
      t.string :validity
      t.string :exchange
      t.string :segment
      t.string :security_id
      t.string :symbol
      t.string :instrument_type
      t.datetime :order_date_time
      t.datetime :exchange_order_time
      t.datetime :last_updated_time
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :broker_orders, :order_no, unique: true
    add_index :broker_orders, :security_id
  end
end
