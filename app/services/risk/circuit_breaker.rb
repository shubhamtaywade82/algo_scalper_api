# frozen_string_literal: true

require 'singleton'

module Risk
  # Emergency halt switch for the entire trading system.
  #
  # When tripped:
  # - EntryGuard blocks all new entries immediately
  # - RiskManagerService force-closes all active positions on next loop (within 5s)
  # - Health endpoint reflects tripped state
  #
  # State persists in Rails.cache (Solid Cache → PostgreSQL), survives process restarts.
  # TTL defaults to 8 hours — auto-resets end-of-day.
  #
  # Usage:
  #   Risk::CircuitBreaker.instance.trip!(reason: 'manual halt')
  #   Risk::CircuitBreaker.instance.tripped?   # => true
  #   Risk::CircuitBreaker.instance.reset!
  #   Risk::CircuitBreaker.instance.status     # => { tripped:, reason:, at: }
  class CircuitBreaker
    include Singleton

    TRIP_CACHE_KEY = 'risk:circuit_breaker:tripped'

    # @return [Boolean] true if circuit breaker is currently tripped
    def tripped?
      !!Rails.cache.read(TRIP_CACHE_KEY)
    rescue StandardError => e
      Rails.logger.error("[CircuitBreaker] tripped? check failed: #{e.message} — failing open")
      false # fail open: don't block trading if cache is unavailable
    end

    # Trip the circuit breaker.
    # @param reason [String] human-readable reason
    # @param ttl [ActiveSupport::Duration] auto-reset duration (default 8h)
    # @return [Hash] current status
    def trip!(reason: nil, ttl: 8.hours)
      payload = { at: Time.current, reason: reason.to_s }
      Rails.cache.write(TRIP_CACHE_KEY, payload, expires_in: ttl)
      Rails.logger.error("[CircuitBreaker] *** TRIPPED *** reason=#{reason.inspect} ttl=#{ttl}")
      status
    rescue StandardError => e
      Rails.logger.error("[CircuitBreaker] trip! failed: #{e.message}")
      raise
    end

    # Reset the circuit breaker — re-enables trading.
    # @return [Boolean] true
    def reset!
      Rails.cache.delete(TRIP_CACHE_KEY)
      Rails.logger.info('[CircuitBreaker] Reset — trading re-enabled')
      true
    rescue StandardError => e
      Rails.logger.error("[CircuitBreaker] reset! failed: #{e.message}")
      raise
    end

    # @return [Hash] { tripped: bool, reason: String|nil, at: Time|nil }
    def status
      data = Rails.cache.read(TRIP_CACHE_KEY)
      return { tripped: false, reason: nil, at: nil } unless data

      { tripped: true, reason: data[:reason], at: data[:at] }
    rescue StandardError => e
      Rails.logger.error("[CircuitBreaker] status failed: #{e.message}")
      { tripped: false, reason: nil, at: nil }
    end

    # Force-close every active position via the provided exit engine.
    # Called by RiskManagerService on each monitor loop while breaker is tripped.
    #
    # @param exit_engine [Live::ExitEngine]
    # @param reason [String] exit reason recorded on each tracker
    def force_close_all!(exit_engine:, reason: 'circuit_breaker')
      trackers = Positions::ActiveForExit.call.to_a
      Rails.logger.error("[CircuitBreaker] Force-closing #{trackers.size} position(s): #{reason}")

      trackers.each do |tracker|
        exit_engine.execute_exit(tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[CircuitBreaker] Force-close failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end
    end
  end
end
