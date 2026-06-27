# frozen_string_literal: true

class AddScalarMetaColumnsToPositionTrackers < ActiveRecord::Migration[7.1]
  def change
    change_table :position_trackers do |t|
      t.boolean  :breakeven_locked, default: false, null: false
      t.decimal  :trailing_stop_price, precision: 12, scale: 4
      t.string   :index_key
      t.string   :direction
      t.string   :entry_path
      t.string   :entry_strategy
      t.string   :exit_path
      t.string   :exit_reason
      t.decimal  :highest_price, precision: 12, scale: 4
      t.decimal  :lowest_price,  precision: 12, scale: 4
      t.boolean  :be_set, default: false, null: false
      t.decimal  :profit_floor_rupees, precision: 12, scale: 4
      t.datetime :profit_floor_set_at
      t.string   :profit_zone_state
      t.datetime :profit_zone_transitioned_at
      t.decimal  :secured_sl_price, precision: 12, scale: 4
      t.decimal  :secured_sl_rupees, precision: 12, scale: 4
      t.string   :carry_mode
      t.datetime :carry_marked_at
      t.decimal  :carry_roi_pct, precision: 8, scale: 4
      t.string   :alpha_source
      t.decimal  :signal_confidence, precision: 8, scale: 4
      t.decimal  :expected_value, precision: 12, scale: 4
      t.datetime :signal_timestamp
      t.string   :client_order_id
    end

    add_index :position_trackers, :index_key
    add_index :position_trackers, :carry_mode
    add_index :position_trackers, :client_order_id
  end
end
