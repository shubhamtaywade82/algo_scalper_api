#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"

require "backtest_engine"

begin
  BacktestEngine::DhanConfiguration.configure_with_env_or_token_endpoint
rescue KeyError, LoadError => e
  warn "DhanHQ configuration skipped: #{e.message}"
end

def print_section(title)
  Rails.logger.debug
  Rails.logger.debug "=" * 90
  Rails.logger.debug title
  Rails.logger.debug "=" * 90
end

def print_result(label, result)
  print_section(label)
  Rails.logger.debug "Trades: #{result.metrics.trades.size}"
  Rails.logger.debug "Skip reasons:"
  result.metrics.skip_reasons.sort_by { |k, _v| k }.each do |reason, count|
    Rails.logger.debug "  - #{reason}: #{count}"
  end
  Rails.logger.debug "Analytics summary:"
  Rails.logger.debug BacktestEngine::Analytics::TradeAnalytics.from_result(result).summary
end

def run_session(index_candles:, option_data:, starting_capital:, lot_size:, **)
  BacktestEngine::BacktestSession
    .new(
      index_candles: index_candles,
      option_data: option_data,
      starting_capital: starting_capital,
      lot_size: lot_size
    )
    .run(BacktestEngine::Strategies::ExpiryTrendV1, **)
end

from = "2025-01-02 09:15:00"
to = "2025-01-31 15:30:00"
expiry_code = 1

starting_capital = 100_000
lot_size = 65

print_section("Loading data (NIFTY, interval=1m, from=#{from}, to=#{to}, expiry_code=#{expiry_code})")

index_candles = BacktestEngine::Data::IndexLoader.fetch(
  interval: 1,
  from: from,
  to: to,
  security_id: BacktestEngine::Data::IndexLoader::NIFTY_SECURITY_ID
)

option_data = BacktestEngine::Data::OptionsLoader.fetch(
  interval: 1,
  from: from,
  to: to,
  expiry_code: expiry_code,
  security_id: BacktestEngine::Data::IndexLoader::NIFTY_SECURITY_ID,
  strikes: BacktestEngine::Data::OptionsLoader::DEFAULT_STRIKES
)

Rails.logger.debug "Index candles: #{index_candles.size}"
Rails.logger.debug "Option series keys: #{option_data.keys.size}"
Rails.logger.debug "Example option series lengths:"
option_data.keys.first(3).each do |key|
  Rails.logger.debug "  - #{key.inspect}: #{option_data[key].size}"
end

result = run_session(
  index_candles: index_candles,
  option_data: option_data,
  starting_capital: starting_capital,
  lot_size: lot_size,
  structure_engine: :v2,
  regime_scorer: true,
  strategy_router: false
)
print_result("Single run (router=false)", result)

days = [{ index_candles: index_candles, option_data: option_data }]

batch = BacktestEngine::BatchRunner.run(
  days: days,
  strategy_class: BacktestEngine::Strategies::ExpiryTrendV1,
  starting_capital: starting_capital,
  lot_size: lot_size,
  structure_engine: :v2,
  regime_scorer: true,
  strategy_router: true
)

print_section("Batch summary (router=true)")
Rails.logger.debug BacktestEngine::Analytics::TradeAnalytics.from_metrics(batch.metrics).summary

print_section("Manual sweep (iv_expansion_period, regime_scorer=true)")

[5, 10, 20].each do |period|
  result = run_session(
    index_candles: index_candles,
    option_data: option_data,
    starting_capital: starting_capital,
    lot_size: lot_size,
    structure_engine: :v2,
    regime_scorer: true,
    strategy_router: true,
    indicator_params: {
      pullback_ema_period: 20,
      volume_spike_period: 10,
      iv_expansion_period: period
    }
  )
  Rails.logger.debug "iv_expansion_period=#{period}: #{BacktestEngine::Analytics::TradeAnalytics.from_result(result).summary}"
end

result = run_session(
  index_candles: index_candles,
  option_data: option_data,
  starting_capital: starting_capital,
  lot_size: lot_size,
  structure_engine: :v2,
  regime_scorer: true,
  strategy_router: true,
  indicator_params: {
    pullback_ema_period: 20,
    volume_spike_period: 10,
    iv_expansion_period: 10
  }
)
print_result("Single run (router=true, indicator_params tuned)", result)

result = run_session(
  index_candles: index_candles,
  option_data: option_data,
  starting_capital: starting_capital,
  lot_size: lot_size,
  structure_engine: :v2,
  regime_scorer: true,
  strategy_router: false,
  indicator_params: { pullback_ema_period: 20, volume_spike_period: 10, iv_expansion_period: 10 }
)
print_result("Single run (router=false, volume params tuned)", result)
