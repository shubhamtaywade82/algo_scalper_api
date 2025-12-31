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

      private

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

