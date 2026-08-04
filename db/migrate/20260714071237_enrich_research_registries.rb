# frozen_string_literal: true

class EnrichResearchRegistries < ActiveRecord::Migration[8.0]
  def change
    # Edge Registry → Portfolio-grade properties
    change_table :research_edge_registry, bulk: true do |t|
      t.float :expected_return                   # avg return from research
      t.float :win_probability                   # success rate 0.0–1.0
      t.float :expected_drawdown                 # worst expected drawdown
      t.string :confidence_interval              # "±6.2%"
      t.string :capacity, default: "unknown"     # high, medium, low
      t.string :expiry_sensitivity               # daily, weekly, monthly
      t.string :market                           # NIFTY, BANKNIFTY, etc.
    end

    # Experiment Registry → Reproducibility + cost tracking
    change_table :research_experiment_registry, bulk: true do |t|
      t.string :dataset_id                       # DS-00001 (immutable snapshot ID)
      t.string :dataset_fingerprint              # SHA256 of the dataset content
      t.integer :cpu_time_ms                     # wall-clock time of experiment
      t.integer :rows_processed, default: 0
      t.integer :features_used, default: 0
      t.jsonb :parent_experiments, default: []   # DAG: experiment IDs this depends on
    end

    # Immutable Dataset Snapshots — each research dataset is fingerprinted
    create_table :research_dataset_snapshots do |t|
      t.string :dataset_id, null: false, index: { unique: true }  # DS-00001
      t.string :symbol, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :session_count, null: false
      t.integer :candle_count, null: false
      t.integer :option_bar_count, default: 0
      t.string :fingerprint, null: false           # SHA256 digest
      t.string :status, default: "active"          # active, superseded
      t.timestamps
    end
  end
end
