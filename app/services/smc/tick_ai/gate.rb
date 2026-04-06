# frozen_string_literal: true

module Smc
  module TickAi
    # Per-index throttle on the WebSocket tick thread (SET NX EX).
    class Gate
      KEY_PREFIX = 'smc:tick_ai:gate'

      class << self
        # @return [Boolean] true if this tick may enqueue a job (lock acquired)
        def acquire(security_id, ttl_seconds:)
          key = "#{KEY_PREFIX}:#{security_id}"
          RedisConnection.client.set(key, '1', nx: true, ex: ttl_seconds.to_i)
        rescue StandardError => e
          Rails.logger.warn("[Smc::TickAi::Gate] acquire failed: #{e.class} - #{e.message}")
          false
        end
      end
    end
  end
end
