# frozen_string_literal: true

module Backtest
  # Builds a Strategies::StrategyContext per bar for backtest replay, serving candles
  # from the backtester's own already-fetched historical data — never
  # Candles::Repository.series/Record, which is only guaranteed a few days deep and
  # silently falls back to a live-only cache for older ranges.
  class StrategyContextAdapter
    TRAILING_LOOKBACK = 6.hours # mirrors Strategies::ContextBuilder#fetch_candles

    def initialize(series_1m:, symbol:)
      @candles_1m = series_1m.candles
      @symbol = symbol
    end

    # @param cutoff [Time] exclusive upper bound — current_candle.timestamp + entry_interval
    # @param params [Hash] resolved strategy params
    # @return [Strategies::StrategyContext]
    def build(cutoff:, params:)
      Strategies::StrategyContext.new(
        instrument_key: @symbol,
        candles: ->(timeframe = "1m") { resample(timeframe, cutoff) },
        indicators: nil,
        session: nil,
        position: nil,
        params: params,
        clock: -> { cutoff },
        config: {}.freeze,
        logger: nil
      )
    end

    private

    def resample(timeframe, cutoff)
      floor = cutoff - TRAILING_LOOKBACK
      prefix = @candles_1m.select { |c| c.timestamp >= floor && c.timestamp < cutoff }
      Candles::Repository.rollup_candles(candles: prefix, symbol: @symbol, timeframe: timeframe)
    end
  end
end
