# frozen_string_literal: true

module MarketState
  # Aggregates signals to determine current market conditions
  class MarketStateEngine
    def initialize(series:, symbol:)
      @series = series
      @symbol = symbol
    end

    # Returns the current market state
    # @return [Hash] { trend: :bullish/:bearish, volatility: :low/:high, session: :morning/... }
    def state
      trend = TrendDetector.bullish?(@series.candles) ? :bullish : :bearish
      volatility = VolatilityDetector.expanding?(@series) ? :high : :low
      session = Strategies::ExpiryModel.session

      {
        trend: trend,
        volatility: volatility,
        session: session,
        timestamp: Time.current
      }
    end
  end
end
