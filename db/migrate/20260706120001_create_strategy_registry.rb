# frozen_string_literal: true

class CreateStrategyRegistry < ActiveRecord::Migration[7.1]
  def change
    create_table :strategies do |t|
      t.string  :slug,   null: false
      t.string  :name,   null: false
      t.string  :status, null: false, default: "draft"
      t.string  :desired_status
      t.references :current_version
      t.timestamps
    end
    add_index :strategies, :slug, unique: true

    create_table :strategy_versions do |t|
      t.references :strategy, null: false
      t.integer :version,     null: false
      t.string  :file_path,   null: false
      t.string  :checksum,    null: false
      t.jsonb   :manifest,    null: false, default: {}
      t.jsonb   :scan_report, default: {}
      t.datetime :deployed_at
      t.timestamps
    end
    add_index :strategy_versions, %i[strategy_id version], unique: true

    create_table :strategy_runs do |t|
      t.references :strategy, null: false
      t.references :strategy_version, null: false
      t.datetime :started_at
      t.datetime :stopped_at
      t.string   :stop_reason
      t.jsonb    :stats, default: {}
      t.timestamps
    end

    create_table :strategy_signals do |t|
      t.references :strategy, null: false
      t.references :strategy_version, null: false
      t.references :strategy_run, null: false
      t.string     :instrument_key, null: false
      t.string     :action,   null: false
      t.float      :confidence
      t.string     :reason
      t.jsonb      :metadata, default: {}
      t.string     :outcome
      t.references :position_tracker
      t.datetime   :emitted_at, null: false
      t.timestamps
    end
    add_index :strategy_signals, %i[strategy_run_id emitted_at]
    add_index :strategy_signals, %i[instrument_key emitted_at]

    create_table :platform_variables do |t|
      t.string  :key,        null: false
      t.string  :value_type, null: false, default: "string"
      t.text    :string_value
      t.decimal :decimal_value, precision: 16, scale: 8
      t.boolean :boolean_value
      t.jsonb   :json_value
      t.text    :description
      t.timestamps
    end
    add_index :platform_variables, :key, unique: true
  end
end
