# frozen_string_literal: true

module Smc
  module Detectors
    class Liquidity
      def initialize(series)
        @series = series
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

      def to_h
        {
          buy_side_taken: buy_side_taken?,
          sell_side_taken: sell_side_taken?,
          sweep_direction: sweep_direction
        }
      end
    end
  end
end

