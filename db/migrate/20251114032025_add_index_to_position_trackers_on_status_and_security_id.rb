class AddIndexToPositionTrackersOnStatusAndSecurityId < ActiveRecord::Migration[8.0]
  def change
    add_index :position_trackers, [:status, :security_id], name: 'index_trackers_on_status_and_security_id'
  end
end
