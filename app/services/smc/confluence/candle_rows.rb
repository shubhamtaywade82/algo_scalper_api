# frozen_string_literal: true

module Smc
  module Confluence
    # Adapts {CandleSeries} / {Candle} to the hash rows expected by {Engine}.
    module CandleRows
      module_function

      # @param series [CandleSeries, nil]
      # @return [Array<Hash>] oldest-first, symbol keys :timestamp (Integer unix), :open, :high, :low, :close, :volume
      def from_series(series)
        return [] if series.nil? || !series.respond_to?(:candles)

        series.candles.map { |c| from_candle(c) }
      end

      # @param candle [Candle]
      def from_candle(candle)
        ts = candle.timestamp
        unix = ts.respond_to?(:to_i) ? ts.to_i : Integer(ts)
        {
          timestamp: unix,
          open: candle.open.to_f,
          high: candle.high.to_f,
          low: candle.low.to_f,
          close: candle.close.to_f,
          volume: candle.respond_to?(:volume) ? candle.volume.to_f : 0.0
        }
      end
    end
  end
end
