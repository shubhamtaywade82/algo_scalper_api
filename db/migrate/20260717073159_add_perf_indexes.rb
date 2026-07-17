class AddPerfIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :position_trackers, :entry_strategy, algorithm: :concurrently, if_not_exists: true
    add_index :strategy_signals, :emitted_at, algorithm: :concurrently, if_not_exists: true
    add_index :instruments, %i[security_id segment], algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :position_trackers, :entry_strategy, algorithm: :concurrently, if_exists: true
    remove_index :strategy_signals, :emitted_at, algorithm: :concurrently, if_exists: true
    remove_index :instruments, %i[security_id segment], algorithm: :concurrently, if_exists: true
  end
end
