# frozen_string_literal: true

class AddPositionSideToPositionTrackers < ActiveRecord::Migration[8.1]
  def change
    add_column :position_trackers, :position_side, :string, default: 'long', null: false
    add_column :position_trackers, :margin_required, :decimal, precision: 12, scale: 2, default: 0
    add_column :position_trackers, :premium_received, :decimal, precision: 10, scale: 2, default: 0
    add_index :position_trackers, %i[position_side status]
  end
end
