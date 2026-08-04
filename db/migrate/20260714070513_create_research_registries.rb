# frozen_string_literal: true

class CreateResearchRegistries < ActiveRecord::Migration[8.0]
  def change
    # 1. Feature Registry — every computed feature has versioned metadata
    create_table :research_feature_registry do |t|
      t.string :feature_id, null: false, index: { unique: true } # F-001, F-002, ...
      t.string :name, null: false                                 # gap_pct, atr, vwap_dist
      t.string :category, null: false                             # auction, momentum, volatility, liquidity
      t.text :description
      t.string :formula                                           # human-readable formula
      t.string :version, null: false, default: "1.0"
      t.jsonb :dependencies, default: []                          # other feature IDs this depends on
      t.string :status, null: false, default: "active"            # active, deprecated
      t.date :introduced_on
      t.date :deprecated_on
      t.timestamps
    end

    # 2. Experiment Registry — every research run is permanently recorded
    create_table :research_experiment_registry do |t|
      t.string :experiment_id, null: false, index: { unique: true } # EXP-00001, EXP-00002, ...
      t.string :question_id                                          # Q-001
      t.text :question_text, null: false
      t.string :hypothesis_description
      t.string :dataset_range                                        # "2024-01-01..2026-07-14"
      t.integer :dataset_size                                        # number of sessions
      t.string :research_version, default: "V7.0"
      t.string :feature_version, default: "V7.0"
      t.string :exit_version, default: "V7.0"
      t.integer :evidence_score, default: 0
      t.jsonb :evidence_details, default: {}                         # sub-metric breakdown
      t.jsonb :distributions, default: {}                            # MFE, MAE, decay, hold CIs
      t.string :verdict, null: false, default: "pending"             # pending, accepted, rejected, inconclusive
      t.string :notebook_path                                        # data/research/notebooks/EXP-XXXX.md
      t.text :rejection_reason
      t.timestamps
    end

    # 3. Edge Registry — every accepted edge is a production model with lifecycle
    create_table :research_edge_registry do |t|
      t.string :edge_id, null: false, index: { unique: true }      # EDGE-001
      t.string :experiment_id, null: false                           # EXP-00042
      t.text :description, null: false
      t.integer :evidence_score, null: false
      t.float :confidence                                            # 0.0 to 1.0
      t.string :regime                                               # bullish, bearish, neutral
      t.integer :sample_size
      t.float :drift_pct, default: 0.0                               # current drift from discovery
      t.string :status, null: false, default: "accepted"             # accepted, production, monitoring, degraded, retired
      t.jsonb :performance, default: {}                              # live paper/production metrics
      t.date :discovered_on
      t.date :last_validated_on
      t.date :retired_on
      t.text :retirement_reason
      t.timestamps
    end

    # 4. Data Quality Audit Log — every data quality check is recorded
    create_table :research_data_quality_audits do |t|
      t.string :symbol, null: false
      t.date :audit_date, null: false
      t.string :status, null: false, default: "pass"                 # pass, warning, fail
      t.integer :total_candles
      t.integer :missing_candles, default: 0
      t.integer :duplicate_candles, default: 0
      t.integer :volume_anomalies, default: 0
      t.integer :timestamp_drift_count, default: 0
      t.boolean :option_chain_complete, default: false
      t.boolean :strike_alignment_ok, default: false
      t.jsonb :details, default: {}                                  # detailed breakdown
      t.timestamps
    end
    add_index :research_data_quality_audits, %i[symbol audit_date], unique: true
  end
end
