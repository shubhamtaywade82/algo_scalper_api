# frozen_string_literal: true

module Validators
  class MarketDataCache
    DEPTH_TTL = 5

    def self.depth_snapshot(security_id)
      cached = redis.get("depth:#{security_id}")
      return JSON.parse(cached, symbolize_names: true) if cached

      nil
    rescue StandardError => e
      Rails.logger.warn("[Validators::MarketDataCache] depth_snapshot failed: #{e.message}")
      nil
    end

    def self.update_depth(security_id, best_bid:, best_ask:, best_bid_qty:, best_ask_qty:)
      redis.setex(
        "depth:#{security_id}", DEPTH_TTL,
        { best_bid: best_bid, best_ask: best_ask,
          best_bid_qty: best_bid_qty, best_ask_qty: best_ask_qty,
          spread: best_ask - best_bid }.to_json
      )
    rescue StandardError => e
      Rails.logger.warn("[Validators::MarketDataCache] update_depth failed: #{e.message}")
      nil
    end

    def self.redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    end
  end
end
