class AddPaperToPositionTrackers < ActiveRecord::Migration[8.0]
  def change
    add_column :position_trackers, :paper, :boolean, default: false, null: false
    add_index :position_trackers, :paper
  end
end
