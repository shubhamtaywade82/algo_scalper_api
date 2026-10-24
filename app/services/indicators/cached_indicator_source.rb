# frozen_string_literal: true

module Indicators
  # Thin adapter that provides a {CandleSeries} from the live Redis cache,
  # falling back to a direct DhanHQ fetch when the cache is cold.
  #
  # Use this in live-trading code paths instead of calling
  # `instrument.candles(interval:)` directly, to avoid redundant DhanHQ REST
  # calls on every tick-analysis cycle and to ensure the series includes
  # backfilled + live tick data.
  #
  # Backtest and script paths should continue to use `instrument.candles`
  # directly — this class is intentionally a live-only adapter.
  #
  # @example In a signal engine or technical analyzer
  #   series = Indicators::CachedIndicatorSource.series_for(instrument: nifty, interval: 5)
  #   series&.rsi(14)
  class CachedIndicatorSource
    class << self
      # Return a {CandleSeries} for the given instrument and interval.
      #
      # The series is fetched from {Live::CandleSeriesCache}. If the cache is
      # thin (< 20 candles), a backfill from DhanHQ is triggered automatically.
      #
      # @param instrument [Instrument] ActiveRecord instrument record
      # @param interval [Integer] candle interval in minutes (e.g. 1, 5, 15)
      # @return [CandleSeries, nil] populated series, or nil on error
      def series_for(instrument:, interval: 5)
        Live::CandleSeriesCache.fetch(instrument: instrument, interval: interval, backfill: true)
      end
    end
  end
end
