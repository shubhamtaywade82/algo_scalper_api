# frozen_string_literal: true

module Smc
  module Detectors
    class Fvg
      def initialize(series)
        @series = series
      end

      def gaps
        gaps = []

        (1...(candles.size - 1)).each do |i|
          prev = candles[i - 1]
          curr = candles[i]
          next_candle = candles[i + 1]

          next unless prev && curr && next_candle

          if curr.bullish? && prev.high < next_candle.low
            gaps << { type: :bullish, from: prev.high, to: next_candle.low }
          elsif curr.bearish? && prev.low > next_candle.high
            gaps << { type: :bearish, from: next_candle.high, to: prev.low }
          end
        end

        gaps
      end

      private

      def candles
        @series&.candles || []
      end
    end
  end
end

