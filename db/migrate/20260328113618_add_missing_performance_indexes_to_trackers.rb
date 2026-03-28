class AddMissingPerformanceIndexesToTrackers < ActiveRecord::Migration[8.1]
  def change
    add_index :position_trackers, [:status, :paper]
    add_index :position_trackers, [:security_id, :segment]
    add_index :position_trackers, [:security_id, :segment, :status], name: 'idx_trackers_on_sid_seg_status'
  end
end
