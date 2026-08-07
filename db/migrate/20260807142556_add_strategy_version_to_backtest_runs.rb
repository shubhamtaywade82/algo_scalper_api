# frozen_string_literal: true

class AddStrategyVersionToBacktestRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :backtest_runs, :strategy_version, foreign_key: { to_table: :strategy_versions }, null: true, index: true
  end
end
