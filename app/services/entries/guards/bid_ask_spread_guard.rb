# frozen_string_literal: true

module Entries
  module Guards
    class BidAskSpreadGuard
      include BaseGuard

      def self.call(context)
        return PASS unless guard_enabled?

        ltp = context[:ltp].to_f
        return PASS unless ltp.positive?

        pick = context[:pick]
        segment = pick[:segment] || context.dig(:index_cfg, :segment)
        security_id = pick[:security_id]
        tick = Live::TickQuery.for_security(segment: segment, security_id: security_id)
        return PASS unless tick

        bid = tick.bid.to_f
        ask = tick.ask.to_f
        return PASS unless bid.positive? && ask.positive? && ask >= bid

        spread_pct = (ask - bid) / ltp
        return PASS if spread_pct <= max_spread_pct

        key = context.dig(:index_cfg, :key) || 'index'
        { blocked: "bid-ask spread too wide for #{key}: #{(spread_pct * 100).round(2)}%" }
      rescue StandardError => e
        # Liquidity quality check — fail open; a quote-fetch glitch shouldn't block entries.
        Rails.logger.warn("[BidAskSpreadGuard] #{e.class} - #{e.message}")
        PASS
      end

      def self.guard_enabled?
        spread_enabled? && max_spread_pct.positive?
      end

      def self.spread_enabled?
        OptionsBuying::Mode.config.dig(:execution, :spread_enabled) == true
      end

      def self.max_spread_pct
        (OptionsBuying::Mode.config.dig(:execution, :max_bid_ask_spread_pct) || 0.015).to_f
      rescue StandardError
        0.015
      end
    end
  end
end
