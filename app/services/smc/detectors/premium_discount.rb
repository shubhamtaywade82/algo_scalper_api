# frozen_string_literal: true

module Smc
  module Detectors
    class PremiumDiscount
      def initialize(series)
        highs = series&.highs || []
        lows = series&.lows || []

        @high = highs.max
        @low = lows.min
        @price = series&.closes&.last
      end

      def equilibrium
        return nil unless @high && @low

        (@high + @low) / 2.0
      end

      def premium?
        eq = equilibrium
        return false unless eq && @price

        @price > eq
      end

      def discount?
        eq = equilibrium
        return false unless eq && @price

        @price < eq
      end

      def to_h
        {
          high: @high,
          low: @low,
          equilibrium: equilibrium,
          price: @price,
          premium: premium?,
          discount: discount?
        }
      end
    end
  end
end

