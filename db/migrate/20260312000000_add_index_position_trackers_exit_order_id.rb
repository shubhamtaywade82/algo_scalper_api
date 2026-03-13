# frozen_string_literal: true

class AddIndexPositionTrackersExitOrderId < ActiveRecord::Migration[8.0]
  def change
    add_index :position_trackers, :exit_order_id, name: 'index_position_trackers_on_exit_order_id'
  end
end
