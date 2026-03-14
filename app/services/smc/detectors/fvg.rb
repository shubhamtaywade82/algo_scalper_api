# frozen_string_literal: true

module Smc
  module Detectors
    class Fvg
      DISPLACEMENT_THRESHOLD = 0.8

      def initialize(series)
        @series = series
      end

      def gaps
        # Only check the last 30 candles for active FVGs
        lookback = [0, candles.size - 30].max

        (lookback...(candles.size - 2)).map do |i|
          detect_fvg(i)
        end.compact
      end

      def active_gaps
        gaps.reject { |g| mitigated?(g) }
      end

      def to_h
        {
          all_gaps: gaps,
          active: active_gaps
        }
      end

      private

      def detect_fvg(i)
        c1 = candles[i]
        c2 = candles[i + 1]
        c3 = candles[i + 2]

        return nil unless c1 && c2 && c3
        return nil unless displacement?(c2)

        if c1.high < c3.low
          { type: :bullish, from: c1.high, to: c3.low, index: i + 1, timestamp: c2.timestamp }
        elsif c1.low > c3.high
          { type: :bearish, from: c3.high, to: c1.low, index: i + 1, timestamp: c2.timestamp }
        end
      end

      def displacement?(candle)
        return false unless candle

        atr = @series.atr(20)
        return true unless atr # Default to true if not enough data for ATR

        body_size = (candle.close - candle.open).abs
        body_size > (atr * DISPLACEMENT_THRESHOLD)
      end

      def mitigated?(gap)
        # Check if any subsequent candle high/low has entered the gap
        start_index = gap[:index] + 2
        return false if start_index >= candles.size

        candles[start_index..].any? do |c|
          if gap[:type] == :bullish
            c.low <= gap[:to] # Price dipped into the gap
          else
            c.high >= gap[:from] # Price rose into the gap
          end
        end
      end

      def candles
        @series&.candles || []
      end
    end
  end
end
