# frozen_string_literal: true

class AddMultiLegSupportToPositions < ActiveRecord::Migration[8.1]
  def change
    # Multi-leg group tracking
    add_column :position_trackers, :leg_group_id, :string
    add_column :position_trackers, :leg_index, :integer, default: 0
    add_column :position_trackers, :leg_role, :string  # 'long_leg', 'short_leg', 'hedge_leg', 'wing_leg'

    add_index :position_trackers, [:leg_group_id, :leg_index]
    add_index :position_trackers, :leg_group_id
  end
end
