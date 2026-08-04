# frozen_string_literal: true

class CreateResearchOptionCandidates < ActiveRecord::Migration[7.1]
  def change
    create_table :research_option_candidates do |t|
      t.references :research_signal, null: false, foreign_key: true
      t.string   :underlying_symbol, null: false
      t.string   :expiry_flag,       null: false # WEEK | MONTH
      t.date     :expiry_date
      t.string   :option_type,       null: false # CE | PE
      t.string   :strike_label,      null: false # ATM, ATM+1, ATM-1, ...
      t.integer  :strike_distance,   null: false, default: 0 # signed steps from ATM (+ = higher strike)
      t.decimal  :actual_strike,     precision: 12, scale: 4
      t.string   :entry_model,       null: false, default: "next_candle_open"
      t.datetime :entry_timestamp
      t.decimal  :entry_price,       precision: 12, scale: 4
      t.datetime :exit_timestamp
      t.decimal  :exit_price,        precision: 12, scale: 4
      t.decimal  :mfe_pct,           precision: 10, scale: 4
      t.decimal  :mae_pct,           precision: 10, scale: 4
      t.decimal  :return_pct,        precision: 10, scale: 4
      t.integer  :holding_minutes
      t.string   :status,            null: false, default: "pending" # pending | scored | no_data | failed
      t.jsonb    :metadata,          null: false, default: {}

      t.timestamps
    end

    add_index :research_option_candidates,
              [:research_signal_id, :expiry_flag, :option_type, :strike_distance, :entry_model],
              unique: true,
              name: "index_research_candidates_on_signal_and_contract"
  end
end
