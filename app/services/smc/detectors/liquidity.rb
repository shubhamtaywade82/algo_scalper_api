# frozen_string_literal: true

module Smc
  module Detectors
    class Liquidity
      # Equal highs/lows threshold (default 0.1 = 10% of range)
      DEFAULT_THRESHOLD = 0.1

      def initialize(series, threshold: DEFAULT_THRESHOLD)
        @series = series
        @threshold = threshold
      end

      def buy_side_taken?
        @series&.liquidity_grab_up? || false
      end

      def sell_side_taken?
        @series&.liquidity_grab_down? || false
      end

      def sweep_direction
        return :buy_side if buy_side_taken?
        return :sell_side if sell_side_taken?

        nil
      end

      # Equal Highs (EQH) - multiple swing highs at similar levels
      def equal_highs?
        highs = recent_highs
        return false if highs.size < 2

        (highs.max - highs.min) <= tolerance
      end

      # Equal Lows (EQL) - multiple swing lows at similar levels
      def equal_lows?
        lows = recent_lows
        return false if lows.size < 2

        (lows.max - lows.min) <= tolerance
      end

      # Sweep detection (liquidity grab)
      def sweep?
        buy_side_taken? || sell_side_taken?
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

      def recent_highs
        @series&.recent_highs(5) || []
      end

      def recent_lows
        @series&.recent_lows(5) || []
      end

      def tolerance
        return 0.0 unless @series&.highs && @series.lows

        range = @series.highs.max - @series.lows.min
        range * @threshold
      end
    end
  end
end
