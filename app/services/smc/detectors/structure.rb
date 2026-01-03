# frozen_string_literal: true

module Smc
  module Detectors
    class Structure
      # Default lookback for swing detection
      # Internal structure uses 1-3, swing structure uses 5-10
      DEFAULT_LOOKBACK = 2

      def initialize(series, lookback: DEFAULT_LOOKBACK)
        @series = series
        @lookback = lookback
      end

      def trend
        return :range if swings.size < 2

        prev, last = swings.last(2)

        if last[:type] == :high && prev[:type] == :low
          :bullish
        elsif last[:type] == :low && prev[:type] == :high
          :bearish
        else
          :range
        end
      end

      def bos?
        last_swing = swings.last
        return false unless last_swing

        close = @series&.closes&.last
        return false unless close

        last_swing[:type] == :high ? close > last_swing[:price] : close < last_swing[:price]
      end

      def choch?
        return false if swings.size < 3

        prev_trend = trend
        new_close = @series&.closes&.last
        return false unless new_close

        case prev_trend
        when :bullish
          new_close < swings.last[:price]
        when :bearish
          new_close > swings.last[:price]
        else
          false
        end
      end

      def swings
        @swings ||= detect_swings
      end

      def to_h
        {
          trend: trend,
          bos: bos?,
          choch: choch?,
          swings: swings.last(10), # Last 10 swings only
          lookback: @lookback
        }
      end

      private

      def detect_swings
        candles = @series&.candles || []
        candles.each_with_index.filter_map do |_candle, i|
          if @series.swing_high?(i, @lookback)
            { type: :high, price: candles[i].high }
          elsif @series.swing_low?(i, @lookback)
            { type: :low, price: candles[i].low }
          end
        end
      end
    end
  end
end

