# frozen_string_literal: true

module Scalp
  # FeeAwareExitTargets — per-position exit targets that respect round-trip friction.
  #
  # PROBLEM: the shipped exit targets are static percentages (percentage_pnl_exit
  # target_pct, exit take_profit). Broker fees are a FLAT Rs.20/order (Rs.40
  # round-trip) regardless of quantity, so the same "5% target" is a real gain on a
  # Rs.150 NIFTY premium but nearly worthless on a Rs.50 SENSEX premium after fees
  # and spread. A scalp that "hits target" while netting zero after friction is a
  # losing trade with extra steps.
  #
  # This service computes, for one position:
  #
  #   friction_pct           fees + estimated spread as a fraction of entry premium
  #   min_target_pct(base)   fee-safe replacement for a static target:
  #                          max(base, min(friction x friction_multiple,
  #                          max_target_pct)) — the cap limits only the fee floor
  #                          so it can never demand the absurd, and the result is
  #                          never lower than base
  #   breakeven_lock_price   the LTP at which a full exit nets >= 0 after the exit
  #                          fee + half spread (per-unit friction spread over qty)
  #   breakeven_armed?       has the position peaked high enough (peak profit as a
  #                          multiple of friction) that locking breakeven is worth it
  #
  # Friction model (per long option position, round trip):
  #   fees_pct   = fee_per_trade / (entry_price * quantity)      -- flat, qty-scaled
  #   spread_pct = spread_rupees / entry_price                    -- per unit premium
  #   friction   = fees_pct + spread_pct
  # The spread is read from the live tick (bid/ask) when available; otherwise the
  # configured default_spread_pct of entry is used (documented estimate — an
  # estimate is exactly what a fallback is for; it errs toward locking slightly
  # early, never toward a net loss).
  #
  # Config (config/algo.yml under risk.scalp_exit — OPT-IN: absent = off):
  #   scalp_exit:
  #     enabled: true
  #     base_target_pct: 0.05        # floor inherited when friction is tiny
  #     friction_multiple: 3.0       # target >= 3x friction
  #     breakeven_arm_factor: 1.2    # arm lock when peak >= 1.2x friction
  #     default_spread_pct: 0.01     # HALF-spread estimate when tick has no bid/ask
  #     max_target_pct: 0.30         # sanity ceiling on the fee-aware floor
  #
  # Data honesty (error-handling review conventions):
  #   * entry_price/quantity unusable -> friction_pct is nil and callers fall back
  #     to the static base target (a guess is worse than the shipped behavior).
  #   * Corrupt config values raise Errors::ConfigurationError (strict read).
  #   * Live::TickQuery.for may raise Errors::InvariantViolation on a corrupt
  #     tracker segment — that propagates (loud), matching the tick-read boundary.
  class FeeAwareExitTargets
    DEFAULTS = {
      base_target_pct: 0.05,
      friction_multiple: 3.0,
      breakeven_arm_factor: 1.2,
      default_spread_pct: 0.01,
      max_target_pct: 0.30
    }.freeze

    NUMERIC_PATTERN = /\A-?\d+(\.\d+)?\z/.freeze

    # @param tracker [PositionTracker] active position (entry_price, quantity, instrument)
    # @param tick [MarketTick, nil] optional pre-fetched tick for the contract
    def initialize(tracker, tick: nil)
      @tracker = tracker
      @entry_price = tracker.entry_price.to_f
      @quantity = tracker.quantity.to_i
      @tick = tick
    end

    class << self
      # Whole-module switch. OPT-IN (wave-2 convention): absent section = off —
      # the dozens of existing spec fixtures that stub AlgoConfig.fetch with
      # partial hashes keep the shipped static-target behaviour untouched. The
      # shipped config/algo.yml enables it explicitly.
      def enabled?
        scalp_cfg[:enabled] == true
      end

      def scalp_cfg
        AlgoConfig.fetch.dig(:risk, :scalp_exit) || {}
      end
    end

    # Friction as a fraction of entry premium, or nil when position economics are
    # unusable (entry/qty missing or non-positive — corrupt tracker data).
    # @return [Float, nil]
    def friction_pct
      return nil unless position_value.positive? && @entry_price.positive?

      fees_pct + spread_pct
    end

    # Fee-safe replacement for a static target percentage.
    # Returns the base target when fee-awareness is disabled or when friction is
    # unknowable — never silently lower than base (the cap constrains only the
    # fee floor, so a base target above max_target_pct is honoured as-is).
    # @param base_target_pct [Float] the static target being replaced
    # @return [Float]
    def min_target_pct(base_target_pct)
      base = base_target_pct.to_f.abs
      return base unless self.class.enabled?

      friction = friction_pct
      return base if friction.nil?

      max_target = cfg_value(:max_target_pct)
      unless max_target.positive?
        raise Errors::ConfigurationError,
              "risk.scalp_exit.max_target_pct must be positive (got #{max_target}) — a negative ceiling " \
              'makes the fee floor clamp raise an untyped ArgumentError'
      end

      fee_floor = (friction * cfg_value(:friction_multiple)).clamp(0.0, max_target)
      [base, fee_floor].max
    end

    # LTP at which exiting the whole position nets >= 0 after the FULL
    # round-trip friction: both order fees (entry + exit = fee_per_trade) and
    # the whole spread (half crossed on entry, half on exit), spread over
    # quantity. The previous exit-side-only version left a locked exit netting
    # minus the entry fee (review P2) — breakeven must mean net-zero on the
    # round trip, not on the exit leg alone.
    # @return [Float, nil] nil when position economics are unusable
    def breakeven_lock_price
      return nil unless @entry_price.positive? && @quantity.positive?

      per_unit_friction = (fee_per_trade + spread_rupees) / @quantity
      (@entry_price + per_unit_friction).round(2)
    end

    # Has the position peaked high enough (as a multiple of friction) that a
    # breakeven lock guarantees "not a net loser" without strangling a young trade?
    # @param peak_profit_pct [Float] peak profit as decimal (0.04 = 4%)
    # @return [Boolean] false when friction is unknowable (no lock on a guess)
    def breakeven_armed?(peak_profit_pct)
      friction = friction_pct
      return false if friction.nil? || friction <= 0

      peak_profit_pct.to_f >= friction * cfg_value(:breakeven_arm_factor)
    end

    # Fees as a fraction of deployed capital (Rs.40 round-trip / position value).
    # Zero when broker fee simulation is disabled (paper without fees).
    # @return [Float]
    def fees_pct
      return 0.0 unless BrokerFeeCalculator.enabled? && position_value.positive?

      BrokerFeeCalculator.fee_per_trade.to_f / position_value
    end

    private

    def position_value
      @position_value ||= (@entry_price * @quantity).to_f
    end

    # Round-trip spread cost as a fraction of entry premium:
    # full spread = 2 x half spread (cross half on entry, half on exit).
    def spread_pct
      spread = spread_rupees
      return 0.0 if spread.nil?

      spread / @entry_price
    end

    # Full round-trip spread in rupees per unit, from the live tick when it
    # carries a usable two-sided quote; otherwise the configured estimate
    # (default_spread_pct is a HALF-spread; the round trip crosses it twice).
    def spread_rupees
      tick_spread_rupees || (@entry_price * cfg_value(:default_spread_pct) * 2.0)
    end

    # Half spread — the cost of crossing the book once (the exit side).
    def half_spread_rupees
      spread_rupees / 2.0
    end

    def tick_spread_rupees
      tick = @tick || Live::TickQuery.for(@tracker)
      return nil unless tick

      bid = tick.bid.to_f
      ask = tick.ask.to_f
      return nil unless bid.positive? && ask >= bid

      ask - bid
    end

    def fee_per_order
      return 0.0 unless BrokerFeeCalculator.enabled?

      BrokerFeeCalculator.fee_per_order.to_f
    end

    # Round-trip order fees (entry + exit) in rupees; zero when broker fee
    # simulation is disabled (paper without fees).
    def fee_per_trade
      return 0.0 unless BrokerFeeCalculator.enabled?

      BrokerFeeCalculator.fee_per_trade.to_f
    end

    # Strict numeric read: absent key -> documented default; garbage raises.
    def cfg_value(key)
      raw = self.class.scalp_cfg[key]
      return DEFAULTS[key].to_f if raw.nil?
      return raw.to_f if raw.is_a?(Numeric)
      return raw.to_f if raw.is_a?(String) && raw.match?(NUMERIC_PATTERN)

      raise Errors::ConfigurationError,
            "risk.scalp_exit.#{key} must be numeric (got #{raw.inspect})"
    end
  end
end
