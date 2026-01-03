# frozen_string_literal: true

module Smc
  module Detectors
    class OrderBlocks
      def initialize(series)
        @series = series
      end

      # Latest bullish order block (from any source)
      def bullish
        all_blocks = internal + swing
        bullish_blocks = all_blocks.select { |b| b[:bias] == :bullish }
        return nil if bullish_blocks.empty?

        # Return the most recent bullish block
        latest = bullish_blocks.last
        find_candle_by_index(latest[:index])
      end

      # Latest bearish order block (from any source)
      def bearish
        all_blocks = internal + swing
        bearish_blocks = all_blocks.select { |b| b[:bias] == :bearish }
        return nil if bearish_blocks.empty?

        # Return the most recent bearish block
        latest = bearish_blocks.last
        find_candle_by_index(latest[:index])
      end

      # Internal order blocks (recent, within last 3 candles)
      def internal
        find_blocks(limit: 3)
      end

      # Swing order blocks (within last 10 candles)
      def swing
        find_blocks(limit: 10)
      end

      def to_h
        {
          bullish: candle_to_h(bullish),
          bearish: candle_to_h(bearish),
          internal: internal.map { |b| block_to_h(b) },
          swing: swing.map { |b| block_to_h(b) }
        }
      end

      private

      def candles
        @series&.candles || []
      end

      def find_blocks(limit:)
        blocks = []

        # Need at least 3 candles to detect order blocks
        return [] if candles.size < 3

        # Check each 3-candle window
        (0...(candles.size - 2)).each do |i|
          a = candles[i]
          b = candles[i + 1]
          c = candles[i + 2]

          next unless a && b && c

          # Bullish OB: bearish candle before bullish impulse
          if a.bearish? && c.close > b.high
            blocks << { bias: :bullish, high: a.high, low: a.low, index: i }
          # Bearish OB: bullish candle before bearish impulse
          elsif a.bullish? && c.close < b.low
            blocks << { bias: :bearish, high: a.high, low: a.low, index: i }
          end
        end

        blocks.last(limit)
      end

      def find_candle_by_index(index)
        candles[index] if index && candles[index]
      end

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

      def block_to_h(block)
        {
          bias: block[:bias],
          high: block[:high],
          low: block[:low],
          index: block[:index]
        }
      end
    end
  end
end

