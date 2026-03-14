# frozen_string_literal: true

module Smc
  module Detectors
    class OrderBlocks
      DISPLACEMENT_THRESHOLD = 0.8

      def initialize(series)
        @series = series
      end

      # Latest unmitigated bullish order block
      def bullish
        active_blocks.select { |b| b[:bias] == :bullish }.last
      end

      # Latest unmitigated bearish order block
      def bearish
        active_blocks.select { |b| b[:bias] == :bearish }.last
      end

      def active_blocks
        find_blocks.reject { |b| mitigated?(b) }
      end

      def find_blocks
        blocks = []
        return [] if candles.size < 5

        # Scan the last 30 candles
        lookback = [0, candles.size - 30].max

        (lookback...(candles.size - 3)).each do |i|
          # We look for: Opposing candle -> Displacement candle -> Optional continuation
          a = candles[i]
          b = candles[i + 1]

          next unless a && b
          next unless displacement?(b)

          if a.bearish? && b.bullish? && b.close > a.high
            blocks << { bias: :bullish, high: a.high, low: a.low, index: i, timestamp: a.timestamp }
          elsif a.bullish? && b.bearish? && b.close < a.low
            blocks << { bias: :bearish, high: a.high, low: a.low, index: i, timestamp: a.timestamp }
          end
        end

        blocks
      end

      def find_candle_by_index(index)
        candles[index] if index && candles[index]
      end

      def to_h
        {
          bullish: bullish,
          bearish: bearish,
          active: active_blocks
        }
      end

      private

      def displacement?(candle)
        return false unless candle

        atr = @series.atr(20)
        return true unless atr

        body_size = (candle.close - candle.open).abs
        body_size > (atr * DISPLACEMENT_THRESHOLD)
      end

      def mitigated?(block)
        start_index = block[:index] + 1
        return false if start_index >= candles.size

        candles[start_index..].any? do |c|
          if block[:bias] == :bullish
            c.low <= block[:low]
          else
            c.high >= block[:high]
          end
        end
      end

      def candles
        @series&.candles || []
      end
    end
  end
end
