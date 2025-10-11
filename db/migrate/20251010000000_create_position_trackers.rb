class CreatePositionTrackers < ActiveRecord::Migration[7.1]
  def change
    create_table :position_trackers do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string  :order_no, null: false
      t.string  :security_id, null: false
      t.string  :symbol
      t.string  :segment
      t.string  :side
      t.string  :status, null: false, default: "pending"
      t.integer :quantity
      t.decimal :avg_price, precision: 12, scale: 4
      t.decimal :entry_price, precision: 12, scale: 4
      t.decimal :last_pnl_rupees, precision: 12, scale: 4
      t.decimal :last_pnl_pct, precision: 8, scale: 4
      t.decimal :high_water_mark_pnl, precision: 12, scale: 4, default: 0
      t.jsonb   :meta, default: {}
      t.timestamps
    end

    add_index :position_trackers, :order_no, unique: true
    add_index :position_trackers, %i[security_id status]
  end
end
