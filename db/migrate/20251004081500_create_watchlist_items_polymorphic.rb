# frozen_string_literal: true

class CreateWatchlistItemsPolymorphic < ActiveRecord::Migration[8.0]
  def change
    create_table :watchlist_items do |t|
      t.string  :segment,       null: false
      t.string  :security_id,   null: false
      t.integer :kind,          null: true
      t.string  :label,         null: true
      t.boolean :active,        null: false, default: true

      # Polymorphic association to Instrument or Derivative
      t.string  :watchable_type
      t.bigint  :watchable_id

      t.timestamps
    end

    add_index :watchlist_items, [ :segment, :security_id ], unique: true
    add_index :watchlist_items, [ :watchable_type, :watchable_id ]
  end
end
