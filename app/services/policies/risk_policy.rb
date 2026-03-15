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
      @proposed_qty = proposed_qty.to_i
      @entry_price  = entry_price.to_f
      @lot_size     = [lot_size.to_i, 1].max
      @violations   = nil
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
      checks = [
        :circuit_breaker_tripped?,
        :max_active_positions_exceeded?,
        :max_exposure_exceeded?,
        :portfolio_drawdown_limit_reached?
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
      max = risk_cfg.dig(:max_active_positions) || 3
      PositionTracker.active.count >= max
    rescue StandardError
      false
    end

    def max_exposure_exceeded?
      max_pct = risk_cfg.dig(:max_exposure_pct).to_f
      return false unless max_pct.positive?

      wallet = Orders.config.gateway.wallet_snapshot
      equity = wallet[:equity].to_f
      return false unless equity.positive?

      proposed_notional  = @entry_price * @proposed_qty
      current_exposure   = wallet[:exposure].to_f
      (current_exposure + proposed_notional) / equity > max_pct
    rescue StandardError
      false
    end

    def portfolio_drawdown_limit_reached?
      result = Live::DailyLimits.new.can_trade?(index_key: @index_key)
      !result[:allowed]
    rescue StandardError
      false
    end

    def risk_cfg
      AlgoConfig.fetch[:risk] || {}
    rescue StandardError
      {}
    end
  end
end
