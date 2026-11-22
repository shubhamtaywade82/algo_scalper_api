# frozen_string_literal: true

require 'json'

module Options
  # Publishes the chain-context payload (contract `chain-context/1`) to Redis
  # after every ChainWatchService refresh, so options-trading-agent can share
  # the analytics instead of re-deriving them from its own chain fetch
  # (infrastructure roadmap G1, "shared chain truth").
  #
  # Error contract (mirrors RedisTickCache's blast-radius boundary):
  #   * Redis outage on publish ... logged + false. The chain watch loop must
  #     keep running; the agent treats a missing/expired key as "fall back to
  #     local computation", which is its pre-existing behaviour.
  #   * unpublishable snapshot .......... skipped silently (from_snapshot
  #     returns nil): stale chains publish nothing rather than frozen walls.
  class ChainContextPublisher
    KEY_PREFIX = 'dhan:chain:context'
    TTL_SECONDS = 15

    def initialize(index_key:, redis: nil)
      @index_key = index_key.to_s.upcase
      @redis = redis || Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    end

    def key
      "#{KEY_PREFIX}:#{@index_key}"
    end

    # Publishes one snapshot; true if written, false otherwise (skipped or
    # Redis down). Called from the chain watch broadcast cycle (~1 s).
    def publish(snapshot)
      payload = ChainContext.from_snapshot(snapshot)
      return false if payload.nil?

      @redis.set(key, JSON.generate(payload), ex: TTL_SECONDS)
      true
    rescue Redis::BaseError, SocketError => e
      Rails.logger.warn("[ChainContextPublisher:#{@index_key}] #{e.class} - #{e.message}")
      false
    end

    # Last published payload, or nil (missing/expired/unreadable). Read side
    # for dashboards and specs; the agent reads the key directly.
    def fetch
      raw = @redis.get(key)
      return nil if raw.nil? || raw.empty?

      JSON.parse(raw)
    end
  end
end
