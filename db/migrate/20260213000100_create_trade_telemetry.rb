# frozen_string_literal: true

class CreateTradeTelemetry < ActiveRecord::Migration[7.1]
  def change
    create_table :trade_telemetry do |t|
      t.references :tracker, null: false, index: false, foreign_key: { to_table: :position_trackers }
      t.string :index_key, null: false
      t.datetime :entry_time, null: false
      t.datetime :exit_time, null: false
      t.string :entry_tf, null: false
      t.string :htf_tf, null: false
      t.integer :bos_age_at_entry
      t.decimal :retrace_pct, precision: 6, scale: 4
      t.integer :pullback_candles
      t.decimal :entry_distance_r, precision: 8, scale: 4
      t.decimal :continuation_body_position, precision: 6, scale: 4
      t.integer :time_from_bos_to_entry
      t.decimal :max_r_reached, precision: 10, scale: 4
      t.decimal :exit_r, precision: 10, scale: 4
      t.string :exit_path
      t.decimal :pnl_rupees, precision: 12, scale: 4
      t.string :trade_state_at_exit
      t.timestamps
    end

    add_index :trade_telemetry, :tracker_id, unique: true
    add_index :trade_telemetry, :index_key
    add_index :trade_telemetry, :entry_time
  end
end
