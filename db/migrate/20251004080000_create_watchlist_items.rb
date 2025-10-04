# frozen_string_literal: true

class CreateWatchlistItems < ActiveRecord::Migration[8.0]
  def change
    create_table :watchlist_items do |t|
      t.string  :segment,     null: false
      t.string  :security_id, null: false
      t.integer :kind,        null: true
      t.string  :label,       null: true
      t.boolean :active,      null: false, default: true

      t.timestamps
    end

    add_index :watchlist_items, [:segment, :security_id], unique: true
  end
end


