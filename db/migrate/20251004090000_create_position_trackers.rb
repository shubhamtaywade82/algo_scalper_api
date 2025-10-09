# frozen_string_literal: true

class CreatePositionTrackers < ActiveRecord::Migration[8.0]
  def change
    create_table :position_trackers do |t|
      t.references :instrument, null: true, foreign_key: true
      t.string :order_no, null: false
      t.string :security_id, null: false
      t.string :exchange_segment
      t.string :transaction_type
      t.string :product_type
      t.string :strategy
      t.decimal :entry_price, precision: 15, scale: 4
      t.decimal :average_price, precision: 15, scale: 4
      t.decimal :exit_price, precision: 15, scale: 4
      t.integer :quantity
      t.string :status, null: false, default: "pending"
      t.decimal :last_pnl_rupees, precision: 15, scale: 2
      t.decimal :high_water_mark_pnl, precision: 15, scale: 2
      t.string :exit_reason

      t.timestamps
    end

    add_index :position_trackers, :order_no, unique: true
    add_index :position_trackers, %i[security_id status]
  end
end
