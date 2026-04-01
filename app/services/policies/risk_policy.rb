# frozen_string_literal: true

module Policies
  # Portfolio-level risk gate checked before opening a new position.
  #
  # Validates that the proposed trade will not breach any of the configured
  # portfolio constraints (max active positions, max exposure, daily drawdown).
  # This runs AFTER signal generation and BEFORE the EntryGuardPipeline so
  # capital-level concerns are separated from signal-level concerns.
  #
  # Usage:
  #   policy = RiskPolicy.new(
  #     index_key:    'NIFTY',
  #     proposed_qty: 50,
  #     entry_price:  245.5
  #   )
  #   policy.permitted?  # => false
  #   policy.reasons     # => ["max_active_positions_exceeded", "max_exposure_exceeded"]
  class RiskPolicy < BasePolicy
    def initialize(index_key:, proposed_qty:, entry_price:, lot_size: 1)
      @index_key    = index_key.to_s
      @proposed_qty = SafeNumeric.to_non_negative_integer(proposed_qty)
      @entry_price  = entry_price.to_f
      @lot_size     = [lot_size.to_i, 1].max
      @violations   = nil
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
        max_active_positions_exceeded?
        per_trade_risk_exceeded?
        max_exposure_exceeded?
        portfolio_drawdown_limit_reached?
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

    def max_active_positions_exceeded?
      max = risk_cfg[:max_active_positions] || 3
      Positions::ActiveForExit.call.count >= max
    rescue StandardError
      false
    end

    def per_trade_risk_exceeded?
      max_pct = per_trade_risk_limit
      return false unless max_pct.positive?

      equity = wallet_snapshot[:equity].to_f
      return false unless equity.positive?

      proposed_notional > (equity * max_pct)
    rescue StandardError
      false
    end

    def max_exposure_exceeded?
      max_pct = risk_cfg[:max_exposure_pct].to_f
      return false unless max_pct.positive?

      equity = wallet_snapshot[:equity].to_f
      return false unless equity.positive?

      current_exposure = wallet_snapshot[:exposure].to_f
      (current_exposure + proposed_notional) / equity > max_pct
    rescue StandardError
      false
    end

    def portfolio_drawdown_limit_reached?
      result = Live::DailyLimits.new.can_trade?(index_key: @index_key)
      return false if result[:allowed]

      %w[trade_frequency_limit_exceeded global_trade_frequency_limit_exceeded].exclude?(result[:reason])
    rescue StandardError
      false
    end

    def risk_cfg
      AlgoConfig.fetch[:risk] || {}
    rescue StandardError
      {}
    end

    def per_trade_risk_limit
      risk_cfg[:max_risk_per_trade_pct].to_f.nonzero? ||
        risk_cfg[:per_trade_risk_pct].to_f
    end

    def proposed_notional
      @entry_price * @proposed_qty
    end

    def wallet_snapshot
      @wallet_snapshot ||= Orders.config.gateway.wallet_snapshot || {}
    rescue StandardError
      {}
    end

    def log_blocked_reasons
      Observability::StructuredLog.warn(
        event: 'risk_policy_blocked',
        payload: {
          service: 'Policies::RiskPolicy',
          index_key: @index_key,
          proposed_qty: @proposed_qty,
          entry_price: @entry_price,
          reasons: reasons
        }
      )
    end
  end
end
