# frozen_string_literal: true

module OptionsBuying
  # Slippage guard checking real market depth (bid-ask spread) before entry
  class SlippageChecker
    # Checks if the bid-ask spread is within acceptable limits.
    # Returns a boolean. True means safe to enter.
    def self.safe_to_enter?(security_id, segment)
      new(security_id, segment).safe_to_enter?
    end

    def initialize(security_id, segment)
      @security_id = security_id.to_s
      @segment = segment.to_s
    end

    def safe_to_enter?
      return true unless enabled?

      tick = Live::TickQuery.for_security(segment: @segment, security_id: @security_id)

      # If depth is unavailable or tick is not full depth, we fallback to simple ltp/close or reject
      return false unless tick

      # We assume the tick provides best bid/ask
      # Currently Tick format has `best_bid_price` and `best_ask_price` or similar
      bid = tick.respond_to?(:best_bid_price) ? tick.best_bid_price.to_f : tick.ltp.to_f
      ask = tick.respond_to?(:best_ask_price) ? tick.best_ask_price.to_f : tick.ltp.to_f

      # If we don't have separate bid/ask, we can't accurately check spread.
      # Return true if fallback is allowed, or false if strict
      return true if bid == ask

      spread_pct = (ask - bid) / ask

      if spread_pct > max_spread_pct
        Rails.logger.warn("[SlippageChecker] Unsafe spread for #{@security_id}. Spread: #{spread_pct * 100}% > Max: #{max_spread_pct * 100}%")
        return false
      end

      true
    end

    private

    def config
      Mode.config[:execution] || {}
    end

    def enabled?
      config[:spread_enabled] == true
    end

    def max_spread_pct
      (config[:max_bid_ask_spread_pct] || 0.015).to_f
    end
  end
end
