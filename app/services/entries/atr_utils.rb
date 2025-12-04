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
        return false if bars.nil? || bars.empty? || bars.size < period * 2

        # Build CandleSeries for efficient ATR calculations
        return false unless bars.first.is_a?(Candle)

        series = CandleSeries.new(symbol: 'temp', interval: '1')
        bars.each { |c| series.add_candle(c) }

        # Calculate ATR for recent periods using sliding windows
        recent_atrs = []
        (period..series.candles.size - 1).each do |i|
          # Create a sub-series for this window
          window_series = CandleSeries.new(symbol: 'temp', interval: '1')
          series.candles[(i - period + 1)..i].each { |c| window_series.add_candle(c) }
          atr = window_series.atr(period)
          recent_atrs << atr if atr
        end

        return false if recent_atrs.size < 3

        # Check if last 3 ATR values are decreasing
        recent_atrs.last(3).each_cons(2).all? { |a, b| b < a }
      end

      # Calculate ATR for a window of candles using CandleSeries
      # @param bars [Array<Candle>] Array of candle objects
      # @return [Float, nil]
      def calculate_atr(bars)
        return nil if bars.nil? || bars.empty? || bars.size < 2

        # Use CandleSeries.atr() method if we have enough candles
        return nil unless bars.first.is_a?(Candle)

        series = CandleSeries.new(symbol: 'temp', interval: '1')
        bars.each { |c| series.add_candle(c) }

        # Use existing CandleSeries.atr() method
        series.atr(14)
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
