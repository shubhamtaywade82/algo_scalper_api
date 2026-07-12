# frozen_string_literal: true

module BacktestEngine
  module Strategies
    class Router
      TRADABLE_REGIMES = %i[trend_bull trend_bear].freeze

      def tradable?(regime:, **)
        return false if regime.nil?

        TRADABLE_REGIMES.include?(regime.to_sym)
      end

      def strategy_for(regime:, **)
        return nil unless tradable?(regime: regime)

        ExpiryTrendV1
      end
    end
  end
end
