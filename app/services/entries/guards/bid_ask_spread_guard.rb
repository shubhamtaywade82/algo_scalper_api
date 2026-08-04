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
        unless tick
          Rails.logger.warn("[BidAskSpreadGuard] No tick data for #{segment}:#{security_id} — skipping spread check")
          return PASS
        end

        bid = tick.bid.to_f
        ask = tick.ask.to_f
        unless bid.positive? && ask.positive? && ask >= bid
          Rails.logger.warn("[BidAskSpreadGuard] bid/ask unavailable for #{segment}:#{security_id} " \
                            "(bid=#{bid}, ask=#{ask}) — skipping spread check")
          return PASS
        end

        spread_pct = (ask - bid) / ltp
        return PASS if spread_pct <= max_spread_pct(context)

        # Quantity / order-depth-aware checks (enabled only when config threshold > 0 and tick has data)
        min_bid_qty = min_bid_qty(context)
        min_ask_qty = min_ask_qty(context)

        if min_bid_qty.to_i.positive? && tick.respond_to?(:bid_qty) && tick.bid_qty.to_i.positive? && tick.bid_qty.to_i < min_bid_qty.to_i
          return { blocked: "bid quantity too shallow (#{tick.bid_qty} < #{min_bid_qty})" }
        end

        if min_ask_qty.to_i.positive? && tick.respond_to?(:ask_qty) && tick.ask_qty.to_i.positive? && tick.ask_qty.to_i < min_ask_qty.to_i
          return { blocked: "ask quantity too shallow (#{tick.ask_qty} < #{min_ask_qty})" }
        end

        PASS
      rescue StandardError => e
        Rails.logger.warn("[BidAskSpreadGuard] #{e.class} - #{e.message}")
        PASS
      end

      def self.guard_enabled?
        spread_enabled? && max_spread_pct({}).positive?
      end

      def self.spread_enabled?
        OptionsBuying::Mode.config.dig(:execution, :spread_enabled) == true
      end

      def self.max_spread_pct(context = {})
        index_cfg = context[:index_cfg] || {}
        index_override = index_cfg.dig(:execution, :max_bid_ask_spread_pct)
        return index_override.to_f if index_override

        (OptionsBuying::Mode.config.dig(:execution, :max_bid_ask_spread_pct) || 0.015).to_f
      rescue StandardError
        0.015
      end

      def self.min_bid_qty(context = {})
        index_cfg = context[:index_cfg] || {}
        index_override = index_cfg.dig(:execution, :min_bid_qty)
        return index_override.to_i if index_override

        (OptionsBuying::Mode.config.dig(:execution, :min_bid_qty) || 0).to_i
      rescue StandardError
        0
      end

      def self.min_ask_qty(context = {})
        index_cfg = context[:index_cfg] || {}
        index_override = index_cfg.dig(:execution, :min_ask_qty)
        return index_override.to_i if index_override

        (OptionsBuying::Mode.config.dig(:execution, :min_ask_qty) || 0).to_i
      rescue StandardError
        0
      end
    end
  end
end
