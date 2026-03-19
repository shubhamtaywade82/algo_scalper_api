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

    def initialize(index_cfg:, direction: nil)
      @index_cfg = index_cfg
      @direction = direction
      @violations = nil
    end

    def permitted?
      allowed = violations.empty?
      log_blocked_reasons unless allowed
      allowed
    end

    def reasons
      violations
    end

    private

    def violations
      @violations ||= compute_violations
    end

    def compute_violations
      checks = %i[
        circuit_breaker_tripped?
        outside_trading_hours?
        daily_loss_limit_reached?
      ]
      checks.each_with_object([]) do |check, acc|
        acc << check.to_s.delete_suffix('?') if send(check)
      end
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

    def daily_loss_limit_reached?
      index_key = @index_cfg&.dig(:key)
      result = Live::DailyLimits.new.can_trade?(index_key: index_key)
      return false if result[:allowed]

      blocked_for_risk_reason?(result[:reason])
    rescue StandardError
      false
    end

    def blocked_for_risk_reason?(reason)
      %w[trade_frequency_limit_exceeded global_trade_frequency_limit_exceeded].exclude?(reason)
    end

    def log_blocked_reasons
      index_key = @index_cfg&.dig(:key).to_s
      Observability::StructuredLog.warn(
        event: 'entry_policy_blocked',
        payload: {
          service: 'Policies::EntryPolicy',
          index_key: index_key,
          direction: @direction.to_s,
          reasons: reasons
        }
      )
    end
  end
end
