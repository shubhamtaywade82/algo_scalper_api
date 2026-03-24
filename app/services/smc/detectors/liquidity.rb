# frozen_string_literal: true

module Smc
  module Detectors
    class Liquidity
      # Threshold for equal levels (percentage of price range)
      # User suggested tick_size * 3 for NIFTY/SENSEX, which is roughly 0.15-0.3 points
      DEFAULT_TOLERANCE = 0.5

      def initialize(series, tolerance: DEFAULT_TOLERANCE)
        @series = series
        @tolerance = tolerance
      end

      def buy_side_taken?
        return false if @series.nil?
        if @series.respond_to?(:liquidity_grab_up?)
          return @series.liquidity_grab_up?
        end

        sweep?(:high)
      end

      def sell_side_taken?
        return false if @series.nil?
        if @series.respond_to?(:liquidity_grab_down?)
          return @series.liquidity_grab_down?
        end

        sweep?(:low)
      end

      def sweep_direction
        return nil if @series.nil?

        return :buy_side if buy_side_taken?
        return :sell_side if sell_side_taken?

        nil
      end

      def sweep?(type)
        return false if swings.empty?

        last_c = candles.last
        return false unless last_c

        if type == :high
          level = recent_swing_highs.first # Most recent high
          return false unless level
          last_c.high > level[:price] && last_c.close < level[:price]
        else
          level = recent_swing_lows.first
          return false unless level
          last_c.low < level[:price] && last_c.close > level[:price]
        end
      end

      # Equal Highs (EQH) - multiple swing highs at similar levels
      def equal_highs?
        highs = recent_swing_highs.pluck(:price).uniq
        return false if highs.size < 2

        (highs.max - highs.min) <= @tolerance
      end

      # Equal Lows (EQL) - multiple swing lows at similar levels
      def equal_lows?
        lows = recent_swing_lows.pluck(:price).uniq
        return false if lows.size < 2

        (lows.max - lows.min) <= @tolerance
      end

      def to_h
        {
          buy_side_taken: buy_side_taken?,
          sell_side_taken: sell_side_taken?,
          sweep_direction: sweep_direction,
          equal_highs: equal_highs?,
          equal_lows: equal_lows?,
          sweep: buy_side_taken? || sell_side_taken?
        }
      end

      private

      def swings
        return [] if @series.nil?

        @swings ||= Structure.new(@series).swings
      end

      def recent_swing_highs
        swings.select { |s| s[:type] == :high }.last(5)
      end

      def recent_swing_lows
        swings.select { |s| s[:type] == :low }.last(5)
      end

      def candles
        @series&.candles || []
      end
    end
  end
end
