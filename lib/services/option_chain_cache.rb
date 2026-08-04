# frozen_string_literal: true

module Services
  class OptionChainCache
    CACHE_PREFIX = 'option_chain'
    DEFAULT_TTL = 3 # seconds (respects DhanHQ rate limit: 1 req / 3s)

    class << self
      def fetch(underlying_key:, expiry:, force_refresh: false)
        cache_key = build_cache_key(underlying_key, expiry)
        cached = force_refresh ? nil : redis.get(cache_key)

        return JSON.parse(cached) if cached

        nil
      end

      def store(underlying_key:, expiry:, chain_data:, ttl: DEFAULT_TTL)
        cache_key = build_cache_key(underlying_key, expiry)
        redis.setex(cache_key, ttl, chain_data.to_json)
      end

      def clear(underlying_key: nil, expiry: nil)
        if underlying_key && expiry
          cache_key = build_cache_key(underlying_key, expiry)
          redis.del(cache_key)
        else
          pattern = underlying_key ? "#{CACHE_PREFIX}:#{underlying_key}:*" : "#{CACHE_PREFIX}:*"
          redis.scan_each(match: pattern) { |key| redis.del(key) }
        end
      end

      private

      def build_cache_key(underlying_key, expiry)
        "#{CACHE_PREFIX}:#{underlying_key}:#{expiry}"
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      end
    end
  end
end
