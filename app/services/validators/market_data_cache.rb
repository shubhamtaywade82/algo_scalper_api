# frozen_string_literal: true

module Validators
  class MarketDataCache
    DEPTH_TTL = 5

    def self.depth_snapshot(security_id)
      cached = Redis.current.get("depth:#{security_id}")
      return JSON.parse(cached, symbolize_names: true) if cached

      nil
    end

    def self.update_depth(security_id, best_bid:, best_ask:, best_bid_qty:, best_ask_qty:)
      Redis.current.setex(
        "depth:#{security_id}", DEPTH_TTL,
        { best_bid: best_bid, best_ask: best_ask,
          best_bid_qty: best_bid_qty, best_ask_qty: best_ask_qty,
          spread: best_ask - best_bid }.to_json
      )
    end
  end
end
