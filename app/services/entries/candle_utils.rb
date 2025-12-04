# frozen_string_literal: true

module Entries
  # Candle pattern utilities
  class CandleUtils
    class << self
      # Calculate average wick-to-body ratio
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Float] Average wick ratio
      def avg_wick_ratio(bars)
        return 0.0 if bars.empty?

        ratios = bars.map { |c| wick_ratio(c) }
        ratios.sum / ratios.size
      end

      # Calculate wick-to-body ratio for a single candle
      # @param candle [Candle] Candle object
      # @return [Float] Wick ratio
      def wick_ratio(candle)
        body = (candle.close - candle.open).abs
        return 0.0 if body.zero?

        upper_wick = candle.high - [candle.open, candle.close].max
        lower_wick = [candle.open, candle.close].min - candle.low
        total_wick = upper_wick + lower_wick

        total_wick / body
      end

      # Check for alternating engulfing candles (noise indicator)
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Boolean]
      def alternating_engulfing?(bars)
        return false if bars.size < 3

        recent = bars.last(3)
        return false if recent.size < 3

        c1 = recent[0]
        c2 = recent[1]
        c3 = recent[2]

        # Check for alternating patterns
        engulfing_12 = engulfing?(c1, c2)
        engulfing_23 = engulfing?(c2, c3)

        # If both are engulfing but in opposite directions
        engulfing_12 && engulfing_23 && c1.bullish? != c3.bullish?
      end

      # Check if candle1 engulfs candle2
      # @param c1 [Candle] First candle
      # @param c2 [Candle] Second candle
      # @return [Boolean]
      def engulfing?(c1, c2)
        c1.high > c2.high && c1.low < c2.low
      end

      # Count inside bars (compression indicator)
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Integer] Count of inside bars
      def inside_bar_count(bars)
        return 0 if bars.size < 2

        count = 0
        (1..bars.size - 1).each do |i|
          prev = bars[i - 1]
          curr = bars[i]

          count += 1 if curr.high <= prev.high && curr.low >= prev.low
        end

        count
      end
    end
  end
end
