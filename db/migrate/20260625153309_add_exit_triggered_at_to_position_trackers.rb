# frozen_string_literal: true

class AddExitTriggeredAtToPositionTrackers < ActiveRecord::Migration[7.1]
  def change
    add_column :position_trackers, :exit_triggered_at, :datetime
    add_index :position_trackers, :exit_triggered_at
  end
end