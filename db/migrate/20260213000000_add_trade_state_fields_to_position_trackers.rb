class AddTradeStateFieldsToPositionTrackers < ActiveRecord::Migration[7.1]
  def change
    add_column :position_trackers, :trade_state, :string
    add_column :position_trackers, :validated_at, :datetime
    add_column :position_trackers, :expansion_at, :datetime
  end
end
