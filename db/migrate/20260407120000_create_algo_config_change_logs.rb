# frozen_string_literal: true

class CreateAlgoConfigChangeLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :algo_config_change_logs do |t|
      t.string :source, null: false
      t.string :actor
      t.string :request_id
      t.jsonb :patch, null: false, default: {}
      t.string :changed_paths, array: true, default: [], null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :algo_config_change_logs, :created_at
    add_index :algo_config_change_logs, :source
  end
end
