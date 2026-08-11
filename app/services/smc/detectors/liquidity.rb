# frozen_string_literal: true

module Smc
  module Detectors
    class Liquidity
      DEFAULT_TOLERANCE = 0.5

      def initialize(series, tolerance: DEFAULT_TOLERANCE)
        @series = series
        @tolerance = tolerance
      end

      def buy_side_taken?
        return false unless @series

        if @series.respond_to?(:liquidity_grab_up?)
          @series.liquidity_grab_up?
        else
          sweep_type?(:high)
        end
      end

      def sell_side_taken?
        return false unless @series

        if @series.respond_to?(:liquidity_grab_down?)
          @series.liquidity_grab_down?
        else
          sweep_type?(:low)
        end
      end

      def sweep_direction
        return :buy_side if buy_side_taken?
        return :sell_side if sell_side_taken?

        nil
      end

      def sweep?
        buy_side_taken? || sell_side_taken?
      end

      def sweep_type?(type)
        return false if swings.empty?

        last_c = candles.last
        return false unless last_c

        if type == :high
          level = recent_swing_highs.first
          return false unless level

          last_c.high > level[:price] && last_c.close < level[:price]
        else
          level = recent_swing_lows.first
          return false unless level

          last_c.low < level[:price] && last_c.close > level[:price]
        end
      end

      def equal_highs?
        return false unless @series

        highs = if @series.respond_to?(:recent_highs)
                  @series.recent_highs(5)
                else
                  recent_swing_highs.pluck(:price).uniq
                end
        return false if highs.blank? || highs.size < 2

        (highs.max - highs.min) <= @tolerance
      end

      def equal_lows?
        return false unless @series

        lows = if @series.respond_to?(:recent_lows)
                 @series.recent_lows(5)
               else
                 recent_swing_lows.pluck(:price).uniq
               end
        return false if lows.blank? || lows.size < 2

        (lows.max - lows.min) <= @tolerance
      end

      def to_h
        {
          buy_side_taken: buy_side_taken?,
          sell_side_taken: sell_side_taken?,
          sweep_direction: sweep_direction,
          equal_highs: equal_highs?,
          equal_lows: equal_lows?,
          sweep: sweep?
        }
      end

      private

      def swings
        return [] unless @series.respond_to?(:candles) && @series.candles&.any?

        @swings ||= Structure.new(@series).swings
      end

      def recent_swing_highs
        swings.select { |s| s[:type] == :high }.last(5)
      end

      def recent_swing_lows
        swings.select { |s| s[:type] == :low }.last(5)
      end

      def candles
        @series.respond_to?(:candles) ? (@series.candles || []) : []
      end
    end
  end
end
