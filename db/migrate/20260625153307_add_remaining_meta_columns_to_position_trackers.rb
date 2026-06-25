# frozen_string_literal: true

class AddRemainingMetaColumnsToPositionTrackers < ActiveRecord::Migration[7.1]
  def change
    change_table :position_trackers, bulk: true do |t|
      # Dynamic lifecycle blobs (used by exit engine/telemetry)
      t.jsonb :decision, default: {}
      t.jsonb :execution, default: {}

      # Entry context blob (dte, sl_pct, tp_pct, trail_pct, volume_velocity_multiplier)
      t.jsonb :entry_context, default: {}

      # Entry scalar fields
      t.integer :dte_at_entry
      t.decimal :vix_at_entry, precision: 8, scale: 4
      t.decimal :iv_at_entry, precision: 8, scale: 4
      t.decimal :iv_percentile, precision: 8, scale: 4
      t.decimal :spread_guard_pct, precision: 8, scale: 4
      t.decimal :atm_strike, precision: 12, scale: 4
      t.date :expiry_date

      # BOS / entry detail scalars
      t.integer :bos_age_at_entry
      t.decimal :retrace_pct, precision: 8, scale: 4
      t.integer :pullback_candles
      t.decimal :entry_distance_r, precision: 12, scale: 4
      t.string :continuation_body_position
      t.string :time_from_bos_to_entry

      # Lifecycle / risk scalars
      t.decimal :premium_stop_price, precision: 12, scale: 4
      t.decimal :entry_risk_rupees, precision: 12, scale: 4
      t.string :entry_tf
      t.string :htf_tf
      t.string :strategy_profile
      t.decimal :entry_underlying_price, precision: 12, scale: 4
      t.decimal :hwm_pnl_pct, precision: 12, scale: 6

      # peak_premium_at is already backed by Redis; keep a DB fallback for display
      t.datetime :peak_premium_at
    end
  end
end
