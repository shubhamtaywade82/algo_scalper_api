class AddPerfIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :position_trackers, :entry_strategy, algorithm: :concurrently, if_not_exists: true
    add_index :strategy_signals, :emitted_at, algorithm: :concurrently, if_not_exists: true
    add_index :instruments, %i[security_id segment], algorithm: :concurrently, if_not_exists: true
  end
end
