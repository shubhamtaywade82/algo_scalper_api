# frozen_string_literal: true

class CreateResearchPremiumLifecycles < ActiveRecord::Migration[7.1]
  def change
    create_table :research_premium_lifecycles do |t|
      t.string   :underlying_symbol, null: false
      t.string   :expiry_flag,       null: false # WEEK | MONTH
      t.string   :option_type,       null: false # CE | PE
      t.string   :strike_label,      null: false # ATM, ATM+1, ATM-1, ...
      t.decimal  :actual_strike,     precision: 12, scale: 4
      t.string   :interval,          null: false, default: "5"

      t.datetime :entry_ts,          null: false
      t.decimal  :entry_premium,     precision: 12, scale: 4

      t.datetime :peak_ts
      t.decimal  :peak_premium,      precision: 12, scale: 4
      t.decimal  :peak_return_pct,   precision: 10, scale: 4
      t.integer  :minutes_to_peak
      t.integer  :peak_duration_minutes

      t.datetime :decay_start_ts

      t.datetime :end_ts
      t.decimal  :end_premium,       precision: 12, scale: 4
      t.decimal  :end_return_pct,    precision: 10, scale: 4

      t.decimal  :max_drawdown_after_peak_pct, precision: 10, scale: 4

      t.jsonb    :threshold_minutes,   null: false, default: {}
      t.jsonb    :underlying_context, null: false, default: {}
      t.string   :status,            null: false, default: "pending" # pending | computed | no_data
      t.jsonb    :metadata,          null: false, default: {}

      t.timestamps
    end

    add_index :research_premium_lifecycles,
              [:underlying_symbol, :expiry_flag, :option_type, :strike_label, :interval, :entry_ts],
              unique: true,
              name: "index_research_lifecycles_on_contract_and_entry"
  end
end
