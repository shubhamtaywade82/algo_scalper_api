# frozen_string_literal: true

module TradeIntents
  # Reads the options-trading-agent heartbeat (agent-snapshot/1), written to Redis every ~2 s with a 10 s TTL.
  # Display only: no Rails trading decision reads it.
  module AgentSnapshot
    KEY = 'trading:agent:snapshot'
    STALE_AFTER_MS = 10_000

    # @return [Hash, nil] the parsed snapshot, or nil when the agent is not publishing
    def self.read(redis: default_redis)
      raw = redis.get(KEY)
      raw && JSON.parse(raw)
    rescue Redis::BaseError, JSON::ParserError => e
      Rails.logger.warn("[TradeIntents::AgentSnapshot] unreadable: #{e.class} - #{e.message}")
      nil
    end

    def self.age_ms(snapshot, now = Time.current)
      updated_at = Time.zone.parse(snapshot['updated_at'].to_s)
      updated_at && ((now - updated_at) * 1000).round
    end

    def self.default_redis
      @default_redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    end
  end
end
