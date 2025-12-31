# frozen_string_literal: true

module Smc
  module Detectors
    class OrderBlocks
      def initialize(series)
        @series = series
      end

      def bullish
        impulse_index = find_impulse(:up)
        return nil unless impulse_index

        candle = candles[impulse_index - 1]
        return nil unless candle&.bearish?

        candle
      end

      def bearish
        impulse_index = find_impulse(:down)
        return nil unless impulse_index

        candle = candles[impulse_index - 1]
        return nil unless candle&.bullish?

        candle
      end

      def to_h
        {
          bullish: candle_to_h(bullish),
          bearish: candle_to_h(bearish)
        }
      end

      private

      def candle_to_h(candle)
        return nil unless candle

        timestamp_value = candle.timestamp
        timestamp_value = timestamp_value.iso8601 if timestamp_value.respond_to?(:iso8601)

        {
          open: candle.open,
          high: candle.high,
          low: candle.low,
          close: candle.close,
          timestamp: timestamp_value
        }
      end

      def candles
        @series&.candles || []
      end

      def find_impulse(direction)
        return nil if candles.size < 2

        (1...candles.size).each do |i|
          curr = candles[i]
          prev = candles[i - 1]
          next unless curr && prev

          if direction == :up
            return i if curr.close > prev.high
          else
            return i if curr.close < prev.low
          end
        end

        nil
      end
    end
  end
end

