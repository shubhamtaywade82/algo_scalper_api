# frozen_string_literal: true

# Shared helpers for strategy plugin specs.
# Provides methods to build fake CandleSeries and StrategyContext
# without needing real DhanHQ data.

module PluginTestHelper
  # Build a CandleSeries with 1m candles for a given trading day.
  # Candles start at 09:15 IST and continue at 1-min intervals.
  #
  # @param base_date [Date] the trading date
  # @param price_fn [Proc] (index, prev_close) -> {open, high, low, close, volume}
  # @param count [Integer] number of 1m candles
  # @param interval [Integer] candle interval in minutes
  # @return [CandleSeries]
  def build_series(base_date:, price_fn:, count: 60, interval: 1)
    series = CandleSeries.new(symbol: 'NIFTY', interval: interval.to_s)
    prev_close = 25_000.0

    count.times do |i|
      t = Time.zone.parse("#{base_date} 09:15:00") + (i * interval.minutes)
      ohlcv = price_fn.call(i, prev_close)
      candle = Candle.new(
        timestamp: t,
        open: ohlcv[:open],
        high: ohlcv[:high],
        low: ohlcv[:low],
        close: ohlcv[:close],
        volume: ohlcv[:volume]
      )
      series.add_candle(candle)
      prev_close = ohlcv[:close]
    end

    series
  end

  # Build a StrategyContext from a CandleSeries, suitable for passing to strategy.call(context)
  # The candles callable returns the series when called with the expected timeframe.
  #
  # @param series [CandleSeries]
  # @param params [Hash] strategy params
  # @param cutoff [Time] the "current" time
  # @return [Strategies::StrategyContext]
  def build_context(series:, params: {}, cutoff: nil)
    cutoff ||= series.candles.last.timestamp

    Strategies::StrategyContext.new(
      instrument_key: series.symbol,
      candles: lambda { |tf = '1m'|
        # In the real adapter, candles are resampled. For tests, we return the
        # series as-is if the timeframe matches, or a rollup approximation.
        if tf == series.interval || tf == '1m'
          series
        else
          # Simple rollup for testing
          Candles::Repository.rollup_candles(candles: series.candles, symbol: series.symbol, timeframe: tf)
        end
      },
      indicators: nil,
      session: nil,
      position: nil,
      params: params,
      clock: -> { cutoff },
      config: {},
      logger: nil
    )
  end

  # Default price function: gentle uptrend with realistic volatility
  def gentle_uptrend_1m
    lambda { |i, prev_close|
      drift = i * 0.5
      noise = (rand - 0.5) * 10
      close = prev_close + drift + noise
      spread = 5 + (rand * 10)
      {
        open: prev_close,
        high: [close, prev_close].max + spread,
        low: [close, prev_close].min - spread,
        close: close,
        volume: rand(100_000..149_999)
      }
    }
  end

  # Steady price with no real trend (for dead-zone / flat VWAP tests)
  def flat_market_1m
    lambda { |_i, _prev_close|
      base = 25_000.0
      noise = (rand - 0.5) * 5
      close = base + noise
      {
        open: base,
        high: close + 3,
        low: close - 3,
        close: close,
        volume: 80_000
      }
    }
  end
end
