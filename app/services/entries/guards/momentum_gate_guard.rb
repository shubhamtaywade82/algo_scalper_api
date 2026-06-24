# frozen_string_literal: true

module Entries
  module Guards
    # Unified momentum gate wrapper for pre-trade validation.
    #
    # Composes three independent detectors into one guard:
    #   1. Bollinger Band breakout on 15-min candles
    #   2. Opening Range Break (ORB) breakout from OptionsBuying::Strategies::OrbBreakout
    #   3. Volume surge confirmation (co-located in the ORB strategy)
    #
    # Entry is allowed if ANY one detector confirms momentum.
    class MomentumGateGuard
      include BaseGuard

      def self.call(context)
        return PASS unless enabled?

        market_state = context[:market_state]
        index_key = (context[:index_cfg] || {})[:key].to_s.upcase
        direction = (context[:pick] || {})[:direction] || (context[:direction] || :bullish)

        bb_pass = bb_breakout?(index_key)
        orb_pass = orb_breakout?(index_key, direction, market_state)

        return PASS if bb_pass
        return PASS if orb_pass

        { blocked: "No momentum signal: BB breakout=false, ORB breakout=false" }
      rescue StandardError => e
        Rails.logger.warn("[MomentumGateGuard] Error: #{e.class} - #{e.message}")
        PASS
      end

      def self.enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :momentum_gate) || {}
        cfg.fetch(:enabled, false)
      end

      def self.bb_breakout?(index_key)
        detector = MarketRegimeDetector.new(index_key: index_key, timeframe: '15')
        detector.bollinger_band_breakout?
      rescue StandardError
        false
      end

      def self.orb_breakout?(index_key, direction, market_state)
        strategy = OptionsBuying::Strategies::OrbBreakout.new(index_key: index_key)
        !!strategy.check_entry(market_state || {})
      rescue StandardError
        false
      end
    end
  end
end
