# frozen_string_literal: true

module Smc
  module Detectors
    class Structure
      def initialize(series)
        @series = series
      end

      def trend
        return :unknown if swings.size < 2

        last, prev = swings.last(2)

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

      private

      def swings
        @swings ||= begin
          candles = @series&.candles || []
          candles.each_with_index.filter_map do |_candle, i|
            if @series.swing_high?(i)
              { type: :high, price: candles[i].high }
            elsif @series.swing_low?(i)
              { type: :low, price: candles[i].low }
            end
          end
        end
      end
    end
  end
end

