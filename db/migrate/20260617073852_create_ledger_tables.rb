# frozen_string_literal: true

class CreateLedgerTables < ActiveRecord::Migration[8.0]
  def change
    create_table :ledger_accounts do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :account_type, null: false
      t.string :currency, null: false, default: 'INR'
      t.decimal :balance_cache, precision: 18, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :ledger_accounts, :code, unique: true, name: 'index_ledger_accounts_on_code_unique'

    create_table :ledger_journal_entries do |t|
      t.string :idempotency_key, null: false
      t.string :event_type, null: false
      t.string :mode, null: false, default: 'paper'
      t.bigint :position_tracker_id
      t.string :order_no
      t.date :trading_date, null: false
      t.jsonb :meta, null: false, default: {}
      t.timestamps
    end
    add_index :ledger_journal_entries, :idempotency_key, unique: true,
              name: 'index_ledger_journal_entries_on_idempotency_key_unique'
    add_index :ledger_journal_entries, :position_tracker_id,
              name: 'index_ledger_journal_entries_on_position_tracker_id'
    add_index :ledger_journal_entries, :trading_date,
              name: 'index_ledger_journal_entries_on_trading_date'
    add_index :ledger_journal_entries, :event_type,
              name: 'index_ledger_journal_entries_on_event_type'

    create_table :ledger_postings do |t|
      t.references :ledger_journal_entry, null: false, foreign_key: true
      t.references :ledger_account, null: false, foreign_key: true
      t.decimal :debit, precision: 18, scale: 2, null: false, default: 0
      t.decimal :credit, precision: 18, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :ledger_postings, %i[ledger_journal_entry_id ledger_account_id],
              name: 'index_ledger_postings_on_journal_and_account'
  end
end
