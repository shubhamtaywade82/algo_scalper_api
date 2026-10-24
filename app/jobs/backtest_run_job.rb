# frozen_string_literal: true

# Runs Backtest::OptionsBuyingBacktester off the request thread — a 90-day backtest makes
# multiple windowed Dhan OHLC calls plus one Options::ExpiredFetcher call per detected entry,
# too slow/network-heavy to run inline in an HTTP request.
#
# No automatic retry_on: a failed run should surface as `failed` for the caller to inspect,
# not silently burn Dhan API calls retrying (mirrors WeeklyCalibrationJob's per-item rescue
# over blanket retry).
class BacktestRunJob < ApplicationJob
  queue_as :background

  def perform(backtest_run_id)
    run = BacktestRun.find(backtest_run_id)
    run.update!(status: 'running', started_at: Time.current)

    engine = if run.strategy_version_id.present?
               Backtest::StrategyBacktester.call(
                 symbol: run.symbol,
                 days_back: run.days_back,
                 strategy_version: run.strategy_version,
                 trading_type: run.trading_type.to_sym,
                 entry_interval: run.entry_interval
               )
             else
               Backtest::OptionsBuyingBacktester.call(
                 symbol: run.symbol,
                 days_back: run.days_back,
                 params: run.params.symbolize_keys,
                 trading_type: run.trading_type.to_sym,
                 entry_interval: run.entry_interval
               )
             end
    summary = engine.summary

    run.update!(
      status: 'completed',
      finished_at: Time.current,
      results: summary,
      total_trades: summary[:total_trades],
      win_rate: summary[:win_rate],
      total_pnl: summary[:total_pnl],
      max_drawdown: summary[:max_drawdown]
    )
  rescue StandardError => e
    Rails.logger.error("[BacktestRunJob] run #{backtest_run_id} failed: #{e.class} - #{e.message}")
    run&.update!(status: 'failed', finished_at: Time.current, error_message: "#{e.class}: #{e.message}")
  end
end
