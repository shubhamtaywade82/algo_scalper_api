# frozen_string_literal: true

class CreateBestIndicatorParams < ActiveRecord::Migration[8.0]
  def change
    create_table :best_indicator_params do |t|
      t.references :instrument, null: false, foreign_key: true, index: true

      # interval such as "1", "5", "15"
      t.string :interval, null: false

      # parameters JSONB (adx_thresh, rsi_lo, rsi_hi, etc.)
      t.jsonb :params, null: false, default: {}

      # metrics JSONB (sharpe, winrate, expectancy, etc.)
      t.jsonb :metrics, null: false, default: {}

      # final score used for ranking (Sharpe Ratio)
      t.decimal :score, precision: 12, scale: 6, null: false, default: 0

      t.timestamps
    end

    # Enforce exactly ONE canonical best row per instrument + interval
    add_index :best_indicator_params,
              [:instrument_id, :interval],
              unique: true,
              name: "idx_unique_best_params_per_instrument_interval"

    # JSONB search optimizations (optional but recommended)
    add_index :best_indicator_params, :params, using: :gin
    add_index :best_indicator_params, :metrics, using: :gin
  end
end

