# frozen_string_literal: true

require "singleton"

module Risk
  class CircuitBreaker
    include Singleton

    TRIP_CACHE_KEY = "risk:circuit_breaker:tripped"

    def tripped?
      !!Rails.cache.read(TRIP_CACHE_KEY)
    end

    def trip!(reason: nil, ttl: 8.hours)
      payload = { at: Time.current, reason: reason }
      Rails.cache.write(TRIP_CACHE_KEY, payload, expires_in: ttl)
      payload
    end

    def reset!
      Rails.cache.delete(TRIP_CACHE_KEY)
      true
    end

    def status
      data = Rails.cache.read(TRIP_CACHE_KEY)
      return { tripped: false } unless data

      { tripped: true, at: data[:at], reason: data[:reason] }
    end
  end
end
