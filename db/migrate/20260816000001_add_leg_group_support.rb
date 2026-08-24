# frozen_string_literal: true

class AddLegGroupSupport < ActiveRecord::Migration[8.1]
  def change
    create_table :leg_groups do |t|
      t.string :group_id, null: false
      t.string :strategy_type, null: false
      t.string :underlying_symbol, null: false
      t.date :expiry, null: false
      t.integer :quantity, null: false, default: 0
      t.string :status, null: false, default: 'pending'
      t.references :instrument, foreign_key: true
      t.jsonb :meta, default: {}
      t.timestamps
    end

    add_index :leg_groups, :group_id, unique: true
    add_index :leg_groups, %i[status strategy_type]
    add_index :leg_groups, :underlying_symbol

    add_column :position_trackers, :leg_group_id, :integer unless column_exists?(:position_trackers, :leg_group_id)
    add_column :position_trackers, :leg_index, :integer, default: 0 unless column_exists?(:position_trackers, :leg_index)
    add_column :position_trackers, :leg_role, :string unless column_exists?(:position_trackers, :leg_role)
    unless column_exists?(:position_trackers, :premium_received)
      add_column :position_trackers, :premium_received, :decimal, precision: 10, scale: 2, default: 0
    end

    add_index :position_trackers, :leg_group_id unless index_exists?(:position_trackers, :leg_group_id)
    add_index :position_trackers, %i[leg_group_id leg_index] unless index_exists?(:position_trackers, %i[leg_group_id leg_index])
  end
end
