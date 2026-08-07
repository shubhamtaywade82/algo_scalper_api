class AddChargesRupeesToPositionTrackers < ActiveRecord::Migration[8.1]
  def change
    # Round-trip (entry + exit leg) real charges, computed and persisted once at exit
    # by Orders::ChargesCalculator. Precision/scale match entry_price/last_pnl_rupees
    # on this same table.
    add_column :position_trackers, :charges_rupees, :decimal, precision: 12, scale: 4
  end
end
