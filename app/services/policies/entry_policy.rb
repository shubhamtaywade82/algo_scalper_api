# frozen_string_literal: true

module Policies
  # High-level entry permission gate.
  #
  # Aggregates the systemic checks that must pass before any entry is even
  # considered, independent of the per-signal guard chain.  The actual
  # per-signal validation lives in Entries::EntryGuardPipeline; this Policy
  # covers the broader system-level conditions.
  #
  # Usage:
  #   policy = EntryPolicy.new(index_cfg: cfg, direction: :long)
  #   policy.permitted?    # => false
  #   policy.reasons       # => ["circuit_breaker_tripped", "outside_trading_hours"]
  #   policy.authorize!    # raises PolicyViolationError if forbidden
  class EntryPolicy < BasePolicy
    MARKET_OPEN  = '09:15'
    MARKET_CLOSE = '15:30'
    # Trade-frequency limits are left to their own guard. Every other DailyLimits refusal is reported under its
    # own reason: they all used to read "daily_loss_limit_reached", which hid which limit had fired.
    TRADE_FREQUENCY_REASONS = %w[trade_frequency_limit_exceeded global_trade_frequency_limit_exceeded].freeze

    def initialize(index_cfg:, direction: nil)
      @index_cfg = index_cfg
      @direction = direction
      @violations = nil
    end

    def permitted?
      violations.empty?
    end

    def reasons
      violations
    end

    private

    def violations
      @violations ||= compute_violations
    end

    def compute_violations
      checks = %i[circuit_breaker_tripped? outside_trading_hours?]
      violations = checks.each_with_object([]) do |check, acc|
        acc << check.to_s.delete_suffix('?') if send(check)
      end
      limits_reason = daily_limits_block_reason
      violations << limits_reason if limits_reason
      violations
    end

    def circuit_breaker_tripped?
      Risk::CircuitBreaker.instance.tripped?
    rescue StandardError
      false
    end

    def outside_trading_hours?
      now          = Time.current
      market_open  = Time.zone.parse(MARKET_OPEN)
      market_close = Time.zone.parse(MARKET_CLOSE)
      !(now >= market_open && now < market_close)
    rescue StandardError
      true # fail-safe: block entries if time cannot be determined
    end

    def daily_limits_block_reason
      result = Live::DailyLimits.new.can_trade?(index_key: @index_cfg&.dig(:key))
      return nil if result[:allowed] || TRADE_FREQUENCY_REASONS.include?(result[:reason])

      result[:reason].to_s.presence || 'daily_limits_blocked'
    rescue StandardError => e
      # Fail closed: an unreadable loss limit must not let an entry through.
      Rails.logger.error("[EntryPolicy] daily limits check failed: #{e.class} - #{e.message}")
      'daily_limits_unavailable'
    end
  end
end
