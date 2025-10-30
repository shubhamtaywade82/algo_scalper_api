# frozen_string_literal: true

class CreatePaperPosition < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_positions do |t|
      t.references :instrument, null: false, foreign_key: true
      t.references :paper_order, null: false, foreign_key: true
      t.string :security_id, null: false
      t.string :symbol
      t.string :segment
      t.string :side, null: false
      t.integer :quantity, null: false
      t.decimal :entry_price, precision: 15, scale: 2, null: false
      t.decimal :current_price, precision: 15, scale: 2
      t.decimal :pnl_rupees, precision: 15, scale: 2, default: 0
      t.decimal :pnl_percent, precision: 10, scale: 4, default: 0
      t.decimal :high_water_mark_pnl, precision: 15, scale: 2, default: 0
      t.string :status, default: 'active'
      t.jsonb :meta, default: {}

      t.timestamps

      t.index :security_id
      t.index :status
    end
  end
end
