# frozen_string_literal: true

module Entries
  # ATR utilities for volatility analysis
  class ATRUtils
    class << self
      # Check if ATR is trending down (volatility compression)
      # @param bars [Array<Candle>] Array of candle objects
      # @param period [Integer] ATR period (default: 14)
      # @return [Boolean]
      def atr_downtrend?(bars, period: 14)
        return false if bars.size < period * 2

        # Calculate ATR for recent periods
        recent_atrs = []
        (period..bars.size - 1).each do |i|
          window = bars[(i - period + 1)..i]
          atr = calculate_atr(window)
          recent_atrs << atr if atr
        end

        return false if recent_atrs.size < 3

        # Check if last 3 ATR values are decreasing
        recent_atrs.last(3).each_cons(2).all? { |a, b| b < a }
      end

      # Calculate ATR for a window of candles
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Float, nil]
      def calculate_atr(bars)
        return nil if bars.size < 2

        true_ranges = []
        (1..bars.size - 1).each do |i|
          prev = bars[i - 1]
          curr = bars[i]

          tr1 = curr.high - curr.low
          tr2 = (curr.high - prev.close).abs
          tr3 = (curr.low - prev.close).abs

          true_ranges << [tr1, tr2, tr3].max
        end

        return nil if true_ranges.empty?

        true_ranges.sum / true_ranges.size
      end

      # Compare current ATR to historical average
      # @param bars [Array<Candle>] Array of candle objects
      # @param current_period [Integer] Current ATR period
      # @param historical_period [Integer] Historical comparison period
      # @return [Float, nil] Ratio (current / historical)
      def atr_ratio(bars, current_period: 14, historical_period: 7)
        return nil if bars.size < current_period + historical_period

        current_window = bars.last(current_period)
        historical_window = bars.last(current_period + historical_period).first(historical_period)

        current_atr = calculate_atr(current_window)
        historical_atr = calculate_atr(historical_window)

        return nil unless current_atr && historical_atr&.positive?

        current_atr / historical_atr
      end
    end
  end
end
