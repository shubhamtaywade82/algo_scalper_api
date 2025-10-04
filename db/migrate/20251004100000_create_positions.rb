class CreatePositions < ActiveRecord::Migration[8.0]
  def change
    create_table :positions do |t|
      t.string :position_key, null: false
      t.string :order_no
      t.string :security_id, null: false
      t.string :product_type
      t.string :position_type
      t.decimal :realized_profit, precision: 18, scale: 6
      t.decimal :unrealized_profit, precision: 18, scale: 6
      t.datetime :closed_at, null: false
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :positions, :position_key, unique: true
    add_index :positions, :security_id
    add_index :positions, :order_no
  end
end
