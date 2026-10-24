# frozen_string_literal: true

module Context
  class Builder
    def self.call(market:, indicators:, regime_state:, index_key: nil, strictness: :strict)
      regime_data = Market::RegimeScorer.new(
        market: market,
        indicators: indicators
      ).call

      state = regime_state.update(regime_data[:regime])

      Domain::TradingContext.new(
        day_type: expiry_day?(index_key) ? :expiry : :normal,
        session: Market::SessionResolver.current,
        regime: state[:regime],
        score: regime_data[:score],
        stability: state[:stability],
        strictness: strictness
      )
    end

    def self.expiry_day?(index_key = nil)
      return Market::ExpiryChecker.expiry_today?(index_key) if index_key.present?

      # Generic fallback when no index context is available (e.g. Strategy::Orchestrator).
      # Thursday covers NIFTY weekly expiry — callers that need precision should pass index_key.
      Time.zone.today.thursday?
    end
  end
end
