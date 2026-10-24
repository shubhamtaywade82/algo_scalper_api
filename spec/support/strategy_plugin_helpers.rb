# frozen_string_literal: true

# Shared helpers for unit-testing strategies/<slug>/strategy.rb plugins directly against
# Strategies::Base#call(context), without going through the full backtester/live daemon.
module StrategyPluginHelpers
  def load_strategy_plugin(slug)
    load Rails.root.join("strategies/#{slug}/strategy.rb").to_s
  end

  def build_plugin_candle(time, open:, high:, low:, close:, volume: 0)
    Candle.new(timestamp: time, open: open, high: high, low: low, close: close, volume: volume)
  end

  def build_plugin_series(candles, symbol: 'NIFTY', interval: '5')
    series = CandleSeries.new(symbol: symbol, interval: interval)
    candles.each { |c| series.add_candle(c) }
    series
  end

  # `series` is returned for any requested timeframe — callers are responsible for building it
  # at the right granularity and ending it exactly at the candle under test, since (unlike the
  # real Backtest::StrategyContextAdapter) this stub does not resample or clip by cutoff.
  def build_plugin_context(series, cutoff:, params: {})
    Strategies::StrategyContext.new(
      instrument_key: series.symbol,
      candles: ->(_timeframe = '5m') { series },
      indicators: nil,
      session: nil,
      position: nil,
      params: params,
      clock: -> { cutoff },
      config: {}.freeze,
      logger: nil
    )
  end
end

RSpec.configure do |config|
  config.include StrategyPluginHelpers, type: :strategy_plugin
end
