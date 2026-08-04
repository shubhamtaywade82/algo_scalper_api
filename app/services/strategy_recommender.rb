# frozen_string_literal: true

# Recommends Supertrend-only entry for all indices in stock mode.
class StrategyRecommender
  class << self
    def best_for_index(symbol:)
      {
        strategy: SupertrendTrend,
        strategy_name: 'SupertrendTrend',
        timeframe: '1m',
        confirmation: nil,
        confidence: 1.0,
        symbol: symbol.to_s.upcase
      }
    end

    def default_recommendation
      {
        strategy_class: SupertrendTrend,
        strategy_name: 'SupertrendTrend',
        timeframe: '1m',
        confirmation: nil
      }
    end
  end
end
