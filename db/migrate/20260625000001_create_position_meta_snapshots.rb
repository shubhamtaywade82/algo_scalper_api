# frozen_string_literal: true

class CreatePositionMetaSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :position_meta_snapshots do |t|
      t.references :position_tracker, null: false, foreign_key: true, index: { unique: true }
      t.string :config_version_hash, null: false
      t.integer :config_change_log_id
      t.jsonb :config_snapshot, null: false, default: {}
      t.datetime :entry_at
      t.string :snapshot_kind, default: 'entry_config'
      t.timestamps
    end
  end
end
