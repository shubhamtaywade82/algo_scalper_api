# frozen_string_literal: true

# Runs the dashboard's SupertrendBacktestStrategy backtest off the request thread. A
# days_back: 365 run makes many windowed Dhan OHLC calls — too slow to hold a Puma worker
# for the whole HTTP request. Status/result live in Rails.cache under a short-lived key
# (no DB table: this is a single ephemeral run report, not something we query/list later —
# BacktestRun/BacktestRunJob already cover the persisted, listable options-buying backtests).
class EquityBacktestJob < ApplicationJob
  queue_as :background

  CACHE_EXPIRY = 30.minutes

  def perform(run_id, symbol:, interval:, days_back:)
    Rails.cache.write(cache_key(run_id), { status: 'running' }, expires_in: CACHE_EXPIRY)
    backtest = BacktestService.run(symbol: symbol, interval: interval, days_back: days_back, strategy: SupertrendBacktestStrategy)
    result = Backtest::EquitySummaryPresenter.call(backtest.summary, symbol: symbol, interval: interval, days_back: days_back)

    Rails.cache.write(cache_key(run_id), { status: 'completed', **result }, expires_in: CACHE_EXPIRY)
  rescue StandardError => e
    Rails.logger.error("[EquityBacktestJob] run #{run_id} failed: #{e.class} - #{e.message}")
    Rails.cache.write(cache_key(run_id), { status: 'failed', error: e.message }, expires_in: CACHE_EXPIRY)
  end

  def self.cache_key(run_id)
    "equity_backtest_run:#{run_id}"
  end

  delegate :cache_key, to: :class
end
