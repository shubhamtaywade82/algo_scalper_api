# frozen_string_literal: true

module Smc
  module Detectors
    class Structure
      # Default lookback for swing detection
      # Internal structure uses 1-3, swing structure uses 5-10
      DEFAULT_LOOKBACK = 3

      def initialize(series, lookback: DEFAULT_LOOKBACK)
        @series = series
        @lookback = lookback
      end

      # Returns the trend based on structural breaks
      def trend
        return :range if bos_history.empty?

        bos_history.last[:type] == :bullish ? :bullish : :bearish
      end

      def bos?
        return false if swings.empty?

        last_high = last_swing_high[:price]
        last_low = last_swing_low[:price]
        close = @series.candles.last.close

        if close > last_high
          { type: :bullish, price: close, index: @series.candles.size - 1 }
        elsif close < last_low
          { type: :bearish, price: close, index: @series.candles.size - 1 }
        else
          false
        end
      end

      def choch?
        return false if swings.size < 3
        return false if bos_history.empty?

        current_trend = trend
        close = @series.candles.last.close

        if current_trend == :bullish && close < last_swing_low[:price]
          { type: :bearish, price: close, index: @series.candles.size - 1, semantic: :choch }
        elsif current_trend == :bearish && close > last_swing_high[:price]
          { type: :bullish, price: close, index: @series.candles.size - 1, semantic: :choch }
        else
          false
        end
      end

      def last_swing_high
        swings.reverse.find { |s| s[:type] == :high }
      end

      def last_swing_low
        swings.reverse.find { |s| s[:type] == :low }
      end

      def swings
        @swings ||= detect_swings
      end

      def bos_history
        @bos_history ||= detect_bos_history
      end

      def to_h
        {
          trend: trend,
          last_bos: bos_history.last,
          last_swing_high: last_swing_high,
          last_swing_low: last_swing_low,
          lookback: @lookback
        }
      end

      private

      def detect_swings
        # Use a 100-candle lookback for swing detection
        lookback_window = [0, @series.candles.size - 100].max
        @series.candles[lookback_window..].each_with_index.filter_map do |_candle, i|
          absolute_index = lookback_window + i
          if @series.swing_high?(absolute_index, @lookback)
            { type: :high, price: @series.candles[absolute_index].high, index: absolute_index }
          elsif @series.swing_low?(absolute_index, @lookback)
            { type: :low, price: @series.candles[absolute_index].low, index: absolute_index }
          end
        end
      end

      def detect_bos_history
        # Simplified: just return based on current relationship
        # Incremental state would ideally be stored in Redis/Database
        []
      end
    end
  end
end
