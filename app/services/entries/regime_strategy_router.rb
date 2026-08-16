# frozen_string_literal: true

module Entries
  # Routes market conditions and regimes to appropriate strategy pipeline:
  # - Buying (Supertrend / Momentum / Breakouts) for trending regimes
  # - Selling (Credit Spreads / Iron Condors) for ranging / choppy regimes
  class RegimeStrategyRouter
    attr_reader :regime, :direction, :index_cfg

    def self.route(regime:, direction:, index_cfg:)
      new(regime: regime, direction: direction, index_cfg: index_cfg).route
    end

    def initialize(regime:, direction:, index_cfg:)
      @regime = regime.to_s.upcase
      @direction = direction
      @index_cfg = index_cfg
    end

    def route
      if selling_regime? && selling_enabled?
        :selling
      elsif buying_regime? && buying_enabled?
        :buying
      else
        :skip
      end
    end

    def strategy_type_for_regime
      if @direction == :bullish
        :bull_put_spread
      else
        :bear_call_spread
      end
    end

    private

    def selling_regime?
      %w[RANGING CHOPPY SIDEWAYS CONSOLIDATING].include?(regime)
    end

    def buying_regime?
      %w[TRENDING_UP TRENDING_DOWN TRENDING].include?(regime)
    end

    def selling_enabled?
      AlgoConfig.fetch.dig(:signals, :strategies_enabled, :selling) == true
    end

    def buying_enabled?
      AlgoConfig.fetch.dig(:signals, :strategies_enabled, :buying) != false
    end
  end
end
