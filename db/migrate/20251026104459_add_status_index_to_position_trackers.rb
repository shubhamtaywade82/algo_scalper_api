class AddStatusIndexToPositionTrackers < ActiveRecord::Migration[8.0]
  def change
    add_index :position_trackers, :status unless index_exists?(:position_trackers, :status)
  end
end
