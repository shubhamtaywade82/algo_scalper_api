class AddExitPriceAndExitedAtToPositionTrackers < ActiveRecord::Migration[8.0]
  def change
    add_column :position_trackers, :exit_price, :decimal, precision: 12, scale: 4
    add_column :position_trackers, :exited_at, :datetime
  end
end
