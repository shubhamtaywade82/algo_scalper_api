# frozen_string_literal: true

module Entries
  # Range utilities for volatility detection
  class RangeUtils
    class << self
      # Calculate percentage range over last N candles
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Float] Range as percentage
      def range_pct(bars)
        return 0.0 if bars.blank?

        highs = bars.filter_map(&:high)
        lows = bars.filter_map(&:low)

        return 0.0 if highs.empty? || lows.empty?

        high = highs.max
        low = lows.min
        avg_price = (high + low) / 2.0

        return 0.0 unless avg_price.positive?

        ((high - low) / avg_price * 100).abs
      end

      # Check if range is compressed (low volatility)
      # @param bars [Array<Candle>] Array of candle objects
      # @param threshold_pct [Float] Threshold percentage (default: 0.1%)
      # @return [Boolean]
      def compressed?(bars, threshold_pct: 0.1)
        range_pct(bars) < threshold_pct
      end
    end
  end
end
