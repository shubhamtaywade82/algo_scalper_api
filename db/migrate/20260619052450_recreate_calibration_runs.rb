# frozen_string_literal: true

class RecreateCalibrationRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :calibration_runs, if_not_exists: true do |t|
      t.string   :symbol, null: false
      t.integer  :weeks_analyzed, null: false, default: 52
      t.string   :strike_mode, null: false, default: 'atm_plus_minus'
      t.jsonb    :raw_stats, null: false, default: {}
      t.jsonb    :proposed_patch, null: false, default: {}
      t.boolean  :is_regime_shift, null: false, default: false
      t.string   :regime_reason
      t.datetime :applied_at
      t.string   :applied_by

      t.timestamps
    end

    add_index :calibration_runs, %i[symbol created_at],
              name: 'index_calibration_runs_on_symbol_and_created_at',
              if_not_exists: true
    add_index :calibration_runs, :applied_at,
              where: 'applied_at IS NOT NULL',
              name: 'index_calibration_runs_on_applied_at_not_null',
              if_not_exists: true
    add_index :calibration_runs, :raw_stats,
              using: :gin,
              name: 'index_calibration_runs_on_raw_stats',
              if_not_exists: true
    add_index :calibration_runs, :proposed_patch,
              using: :gin,
              name: 'index_calibration_runs_on_proposed_patch',
              if_not_exists: true
  end
end
