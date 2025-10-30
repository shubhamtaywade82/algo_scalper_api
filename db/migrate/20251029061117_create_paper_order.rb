# frozen_string_literal: true

class CreatePaperOrder < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_orders do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :order_no, null: false
      t.string :correlation_id
      t.string :security_id, null: false
      t.string :segment, null: false
      t.string :symbol
      t.string :transaction_type, null: false
      t.string :order_type, default: 'MARKET'
      t.string :product_type, default: 'INTRADAY'
      t.integer :quantity, null: false
      t.decimal :price, precision: 15, scale: 2
      t.decimal :executed_price, precision: 15, scale: 2
      t.string :status, default: 'pending'
      t.text :error_message
      t.jsonb :meta, default: {}

      t.timestamps

      t.index :order_no, unique: true
      t.index :security_id
      t.index :status
    end
  end
end
