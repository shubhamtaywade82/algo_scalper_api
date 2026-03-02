# frozen_string_literal: true

class AddExitIntentFieldsToPositionTrackers < ActiveRecord::Migration[8.0]
  def change
    add_column :position_trackers, :exit_requested_at, :datetime
    add_column :position_trackers, :exit_sent_at, :datetime
    add_column :position_trackers, :exit_coid, :string
    add_column :position_trackers, :exit_order_id, :string

    add_index :position_trackers, :exit_requested_at
    add_index :position_trackers, :exit_coid, unique: true
  end
end
