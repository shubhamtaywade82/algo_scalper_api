# frozen_string_literal: true

module Context
  class Builder
    def self.call(market:, indicators:, regime_state:)
      regime_data = Market::RegimeScorer.new(
        market: market,
        indicators: indicators
      ).call

      state = regime_state.update(regime_data[:regime])

      Domain::TradingContext.new(
        day_type: expiry_day? ? :expiry : :normal,
        session: Market::SessionResolver.current,
        regime: state[:regime],
        score: regime_data[:score],
        stability: state[:stability]
      )
    end

    def self.expiry_day?
      today = Date.today
      today.thursday?
    end
  end
end
