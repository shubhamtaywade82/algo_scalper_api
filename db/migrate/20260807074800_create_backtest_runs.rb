class CreateBacktestRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :backtest_runs do |t|
      t.string :symbol, null: false
      t.integer :days_back, null: false, default: 90
      t.string :trading_type, null: false, default: 'options'
      t.string :entry_interval, null: false, default: '5'
      t.jsonb :params, default: {}, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :total_trades
      t.decimal :win_rate, precision: 8, scale: 4
      t.decimal :total_pnl, precision: 12, scale: 4
      t.decimal :max_drawdown, precision: 12, scale: 4
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :results, default: {}, null: false

      t.timestamps
    end

    add_index :backtest_runs, :status
    add_index :backtest_runs, :created_at
  end
end
