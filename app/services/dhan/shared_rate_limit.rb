# frozen_string_literal: true

module Dhan
  # Dhan enforces its limits per account, but DhanHQ::RateLimiter only counts inside one process.
  # Web, jobs and the trading daemon share one account, so every throttled call first reserves
  # a spaced slot in Redis. Prepended onto DhanHQ::RateLimiter in an initializer.
  module SharedRateLimit
    SLOT_GAP_SECONDS = { quote_api: 1.0, data_api: 0.2, option_chain: 3.0 }.freeze
    MAX_WAIT_SECONDS = 10.0
    KEY_PREFIX = 'dhan:rate_limit'

    # Atomically hands out the next free slot and pushes the following one `gap` seconds later.
    RESERVE_SLOT = <<~LUA
      local now = tonumber(ARGV[1])
      local gap = tonumber(ARGV[2])
      local next_free = tonumber(redis.call('GET', KEYS[1]) or '0')
      local slot = math.max(now, next_free)
      redis.call('SET', KEYS[1], tostring(slot + gap), 'PX', 60000)
      return tostring(slot)
    LUA

    def self.redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    end

    def throttle!
      wait_for_shared_slot
      super
    end

    private

    # Fails open: a Redis outage must not stop trading; the gem's in-process limiter still applies.
    def wait_for_shared_slot
      gap = SLOT_GAP_SECONDS[@api_type]
      return unless gap

      now = Time.now.to_f
      slot = Dhan::SharedRateLimit.redis.eval(RESERVE_SLOT, keys: ["#{KEY_PREFIX}:#{@api_type}"], argv: [now, gap]).to_f
      wait = [slot - now, MAX_WAIT_SECONDS].min
      sleep(wait) if wait.positive?
    rescue StandardError => e
      Rails.logger.warn("[Dhan::SharedRateLimit] #{@api_type} slot reservation failed, using in-process limit only: #{e.class} - #{e.message}")
    end
  end
end
