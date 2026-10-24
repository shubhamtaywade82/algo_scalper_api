# frozen_string_literal: true

class CreateReconciliationTables < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_runs do |t|
      t.string :status, null: false, default: 'running'  # running, passed, failed, error
      t.string :mode, null: false, default: 'paper'       # paper / live
      t.integer :orders_checked, default: 0, null: false
      t.integer :positions_checked, default: 0, null: false
      t.integer :funds_checked, default: 0, null: false
      t.integer :discrepancies_found, default: 0, null: false
      t.boolean :halted_trading, default: false, null: false
      t.jsonb :summary, default: {}, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :reconciliation_runs, :status
    add_index :reconciliation_runs, :created_at

    create_table :reconciliation_discrepancies do |t|
      t.references :reconciliation_run, null: false, foreign_key: true
      t.string :entity_type, null: false     # order, position, fund
      t.string :entity_id                     # broker order_id, security_id, etc.
      t.string :field_name, null: false       # status, quantity, price, etc.
      t.string :local_value
      t.string :broker_value
      t.string :severity, null: false, default: 'warning'  # info, warning, critical
      t.string :resolution                    # auto_fixed, manual, ignored, pending
      t.text :notes
      t.timestamps
    end

    add_index :reconciliation_discrepancies, :entity_type
    add_index :reconciliation_discrepancies, :severity
  end
end
