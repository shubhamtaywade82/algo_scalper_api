# frozen_string_literal: true

class CreateTradingCoreTables < ActiveRecord::Migration[8.0]
  def change
    create_table :instruments do |t|
      t.string :security_id, null: false
      t.string :exchange_segment, null: false
      t.string :symbol_name, null: false
      t.boolean :enabled, null: false, default: false
      t.jsonb :metadata

      t.timestamps
    end

    add_index :instruments, :security_id, unique: true
    add_index :instruments, :symbol_name

    create_table :derivatives do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :security_id, null: false
      t.decimal :strike_price, precision: 12, scale: 2, null: false
      t.date :expiry_date, null: false
      t.string :option_type, null: false
      t.integer :lot_size, null: false, default: 1
      t.string :exchange_segment, null: false

      t.timestamps
    end

    add_index :derivatives, [ :security_id ], unique: true
    add_index :derivatives, [ :instrument_id, :expiry_date ]
    add_index :derivatives, [ :instrument_id, :option_type, :expiry_date ]

    create_table :position_trackers do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :order_no, null: false
      t.string :security_id, null: false
      t.string :status, null: false, default: "pending"
      t.decimal :entry_price, precision: 12, scale: 2
      t.integer :quantity
      t.decimal :last_pnl_rupees, precision: 14, scale: 2
      t.decimal :high_water_mark_pnl, precision: 14, scale: 2, default: 0

      t.timestamps
    end

    add_index :position_trackers, :order_no, unique: true
    add_index :position_trackers, :security_id
    add_index :position_trackers, :status
  end
end
