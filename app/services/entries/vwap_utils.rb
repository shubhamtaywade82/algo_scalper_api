# frozen_string_literal: true

module Entries
  # VWAP utilities (works without volume - uses typical price)
  class VWAPUtils
    class << self
      # Check if price is near VWAP (within threshold %)
      # @param bars [Array<Candle>] Array of candle objects
      # @param threshold_pct [Float] Threshold percentage (default: 0.1%)
      # @return [Boolean]
      def near_vwap?(bars, threshold_pct: 0.1)
        return false if bars.nil? || bars.empty?

        current_price = bars.last&.close
        return false unless current_price&.positive?

        vwap = calculate_vwap(bars)
        return false unless vwap&.positive?

        deviation_pct = ((current_price - vwap).abs / vwap * 100).abs
        deviation_pct <= threshold_pct
      end

      # Check for VWAP chop: price within ±threshold% for N+ candles
      # @param bars [Array<Candle>] Array of candle objects
      # @param threshold_pct [Float] Threshold percentage (e.g., 0.08 for NIFTY, 0.06 for SENSEX)
      # @param min_candles [Integer] Minimum candles in chop (e.g., 3 for NIFTY, 2 for SENSEX)
      # @return [Boolean]
      def vwap_chop?(bars, threshold_pct:, min_candles:)
        return false if bars.nil? || bars.empty? || bars.size < min_candles

        vwap = calculate_vwap(bars)
        return false unless vwap&.positive?

        # Check last N candles
        recent_bars = bars.last(min_candles)
        recent_bars.all? do |candle|
          price = candle.close
          next false unless price&.positive?

          deviation_pct = ((price - vwap).abs / vwap * 100).abs
          deviation_pct <= threshold_pct
        end
      end

      # Calculate VWAP (using typical price when volume unavailable)
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Float, nil]
      def calculate_vwap(bars)
        return nil if bars.empty?

        # Use typical price (HLC/3) as proxy when volume unavailable
        typical_prices = bars.map { |c| (c.high + c.low + c.close) / 3.0 }
        typical_prices.sum / typical_prices.size
      end

      # Calculate AVWAP (Anchored VWAP from session open)
      # @param bars [Array<Candle>] Array of candle objects
      # @param anchor_time [Time] Anchor time (default: 9:15 AM)
      # @return [Float, nil]
      def calculate_avwap(bars, anchor_time: nil)
        return nil if bars.empty?

        # Filter bars from anchor time
        anchor = anchor_time || bars.first.timestamp
        anchored_bars = bars.select { |c| c.timestamp >= anchor }
        return nil if anchored_bars.empty?

        calculate_vwap(anchored_bars)
      end

      # Check if price is between VWAP and AVWAP (trapped)
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Boolean]
      def trapped_between_vwap_avwap?(bars)
        return false if bars.empty?

        current_price = bars.last.close
        vwap = calculate_vwap(bars)
        avwap = calculate_avwap(bars)

        return false unless vwap && avwap

        # Check if price is between the two
        [vwap, avwap].min <= current_price && current_price <= [vwap, avwap].max
      end
    end
  end
end
