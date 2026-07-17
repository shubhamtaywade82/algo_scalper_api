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
        # Current bar BOS as fallback when history is empty (e.g. short series)
        if (cur = bos?)
          return cur[:type] == :bullish ? :bullish : :bearish
        end

        bos_history.last[:type] == :bullish ? :bullish : :bearish
      end

      def bos?
        return false if swings.empty?

        last_high = last_swing_high&.dig(:price)
        last_low = last_swing_low&.dig(:price)
        return false unless last_high && last_low

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

      # Build BOS history from swings and closes so trend can be bullish/bearish.
      # Only considers candle close vs last confirmed swing high/low (body close, not wick).
      def detect_bos_history
        history = []
        return history if swings.size < 2

        arr = @series.candles
        min_i = @lookback
        max_i = arr.size - 1

        if max_i >= min_i
          reversed_swings = swings.reverse
          (min_i..max_i).each do |i|
            close = arr[i].close
            last_high = reversed_swings.find { |s| s[:type] == :high && s[:index] + @lookback <= i }
            last_low = reversed_swings.find { |s| s[:type] == :low && s[:index] + @lookback <= i }
            next unless last_high && last_low

            if close > last_high[:price]
              history << { type: :bullish, price: close, index: i }
            elsif close < last_low[:price]
              history << { type: :bearish, price: close, index: i }
            end
          end
        end

        # When window is too short, add current-bar BOS if it breaks structure (at most one)
        if history.empty? && arr.any? && last_swing_high && last_swing_low
          close = arr.last.close
          if close > last_swing_high[:price]
            history << { type: :bullish, price: close, index: arr.size - 1 }
          elsif close < last_swing_low[:price]
            history << { type: :bearish, price: close, index: arr.size - 1 }
          end
        end
        history
      end
    end
  end
end
