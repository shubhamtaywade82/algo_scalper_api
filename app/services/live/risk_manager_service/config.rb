# frozen_string_literal: true

module Live
  class RiskManagerService
    # Config resolution for the 5-layer risk enforcement system.
    #
    # Error-handling contract (error-handling review 2026-09, wave 3): this
    # layer resolves stop-loss, take-profit and exit-layer thresholds. A
    # corrupt config document must NEVER silently degrade to defaults here —
    # every `rescue -> {}/nil/default` in this module used to convert a
    # configuration fault into either (a) exit layers silently disabled, or
    # (b) exit layers running on manufactured thresholds nobody configured.
    #
    # AlgoConfig.fetch is strict (wave 1); the per-tracker enforcement methods
    # have logged isolation rescues, so a propagated ConfigurationError
    # surfaces loudly on every enforcement cycle instead of masquerading as
    # "no risk config".
    #
    # Documented defaults below apply ONLY to absent keys — an operator who
    # set a value must get that value (or a loud error), never a quiet
    # substitution.
    module Config
      DEFAULT_TICK_STALE_AFTER_SECONDS = 3.0
      DEFAULT_MIN_ENFORCEMENT_GAP_SECONDS = 0.25

      private

      def risk_config
        raw = resolved_risk_config
        return {} if raw.blank?

        cfg = raw.dup
        # Alias resolution only — values pass through untouched; invalid
        # values stay visible to the enforcement layer that consumes them.
        cfg[:stop_loss_pct] = raw[:stop_loss_pct] || raw[:sl_pct]
        cfg[:take_profit_pct] = raw[:take_profit_pct] || raw[:tp_pct]
        cfg[:sl_pct] = cfg[:stop_loss_pct]
        cfg[:tp_pct] = cfg[:take_profit_pct]
        cfg[:breakeven_after_gain] = raw.key?(:breakeven_after_gain) ? raw[:breakeven_after_gain] : 0
        cfg[:trail_step_pct] = raw[:trail_step_pct] if raw.key?(:trail_step_pct)
        cfg[:exit_drop_pct] = raw[:exit_drop_pct] if raw.key?(:exit_drop_pct)
        cfg[:time_exit_hhmm] = raw[:time_exit_hhmm] if raw.key?(:time_exit_hhmm)
        cfg[:market_close_hhmm] = raw[:market_close_hhmm] if raw.key?(:market_close_hhmm)
        cfg[:min_profit_rupees] = raw[:min_profit_rupees] if raw.key?(:min_profit_rupees)
        cfg
      end

      # Merge exit-related config from the legacy location (:position_sizing) and the canonical location (:risk).
      # Canonical (:risk) wins on conflicts.
      def resolved_risk_config
        cfg = algo_config
        legacy = cfg[:position_sizing].is_a?(Hash) ? cfg[:position_sizing] : {}
        risk = cfg[:risk].is_a?(Hash) ? cfg[:risk] : {}
        legacy.merge(risk)
      end

      def hard_rupee_sl_enabled?
        cfg = hard_rupee_sl_config
        cfg && cfg[:enabled] == true
      end

      def hard_rupee_tp_enabled?
        cfg = hard_rupee_tp_config
        cfg && cfg[:enabled] == true
      end

      def hard_rupee_sl_config
        algo_config.dig(:risk, :hard_rupee_sl)
      end

      def hard_rupee_tp_config
        algo_config.dig(:risk, :hard_rupee_tp)
      end

      def profit_floor_config
        raw = algo_config.dig(:risk, :profit_floor) || {}

        {
          enabled: raw[:enabled] == true,
          lock_rupees: integer_or_nil(raw[:lock_rupees]),
          breakeven_at: integer_or_nil(raw[:breakeven_at]),
          time_kill_minutes: integer_or_nil(raw[:time_kill_minutes])
        }
      end

      def rr_profit_booking_config
        algo_config.dig(:risk, :rr_profit_booking) || {}
      end

      def rr_profit_booking_enabled?
        rr_profit_booking_config[:enabled] == true
      end

      # Parse helper for OPTIONAL integer keys: nil in = nil out; garbage
      # yields nil (documented unknown -> feature step skipped). Required
      # values must not go through here.
      def integer_or_nil(value)
        return nil if value.nil?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def safe_big_decimal(value)
        return nil if value.nil?

        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def post_profit_zone_enabled?
        cfg = post_profit_zone_config
        cfg && cfg[:enabled] != false
      end

      # Absent keys use the documented defaults below (raw wins via merge).
      # A corrupt config document propagates — it used to return the full
      # default set (2000/4000/800), i.e. the exit layer kept running on
      # thresholds nobody configured.
      def post_profit_zone_config
        raw = algo_config.dig(:risk, :post_profit_zone) || {}

        # Defaults
        {
          enabled: true,
          secured_profit_threshold_rupees: raw[:secured_profit_threshold_rupees] || 2000,
          runner_zone_threshold_rupees: raw[:runner_zone_threshold_rupees] || 4000,
          secured_sl_rupees: raw[:secured_sl_rupees] || 800,
          underlying_adx_min: raw[:underlying_adx_min] || 18.0,
          option_pullback_max_pct: raw[:option_pullback_max_pct] || 35.0,
          underlying_atr_collapse_threshold: raw[:underlying_atr_collapse_threshold] || 0.65,
          runner_zone_momentum_check: raw[:runner_zone_momentum_check] || false
        }.merge(raw)
      end

      def iv_collapse_detection_enabled?
        config = algo_config.dig(:risk, :time_overrides, :iv_collapse) || {}
        config[:enabled] == true
      end

      def stall_detection_enabled?
        config = stall_detection_config
        config[:enabled] == true
      end

      def stall_detection_config
        algo_config.dig(:risk, :time_overrides, :stall_detection) || {}
      end

      # Configuration helpers for new 5-layer exit system
      #
      # Absent section = layer ON (fail-safe direction for exit layers —
      # documented default). A corrupt config document propagates (wave 3):
      # it used to read as "enabled", hiding the breakage while the layer
      # ran on unknown parameters.

      def structure_invalidation_enabled?
        config = algo_config.dig(:risk, :exits, :structure_invalidation) || {}
        config.fetch(:enabled, true) # Default: enabled
      end

      def premium_momentum_failure_enabled?
        config = algo_config.dig(:risk, :exits, :premium_momentum_failure) || {}
        config.fetch(:enabled, true) # Default: enabled
      end

      def time_stop_enabled?
        config = algo_config.dig(:risk, :exits, :time_stop) || {}
        config.fetch(:enabled, true) # Default: enabled
      end

      # Strict single source: the shared @algo_config memo (populated strictly
      # in #initialize). No blanket rescue — see module contract above.
      def algo_config
        @algo_config ||= AlgoConfig.fetch
      end

      # Percentage parse for decision inputs (RR ratios, booking targets).
      # Garbage used to become BigDecimal(0) — silently disabling the booking
      # target or manufacturing a zero stop. 0 is a REAL percentage; only an
      # actual zero input may produce it.
      def pct_value(value)
        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError => e
        raise Errors::ConfigurationError,
              "unparseable percentage #{value.inspect} (#{e.class}: #{e.message})"
      end

      def realtime_config
        cfg = algo_config
        top_level = cfg[:realtime].is_a?(Hash) ? cfg[:realtime] : {}
        risk_level = cfg.dig(:risk, :realtime).is_a?(Hash) ? cfg.dig(:risk, :realtime) : {}
        top_level.merge(risk_level)
      end

      # Absent key -> documented default. Explicitly configured flags are
      # honoured as-is; no blanket rescue (wave 3).
      def realtime_tick_first_enabled?
        cfg = realtime_config
        return true unless cfg.key?(:tick_first_enabled)

        cfg[:tick_first_enabled] == true
      end

      def realtime_fallback_enabled?
        cfg = realtime_config
        return true unless cfg.key?(:fallback_enabled)

        cfg[:fallback_enabled] == true
      end

      # Absent -> documented default. Present-but-invalid (unparseable or
      # <= 0) raises: a typo'd staleness window must not silently become
      # 3.0s while the operator believes their value is active.
      def realtime_tick_stale_after_seconds
        raw = realtime_config[:tick_stale_after_seconds]
        return DEFAULT_TICK_STALE_AFTER_SECONDS if raw.nil?

        value = Float(raw)
        unless value.positive?
          raise Errors::ConfigurationError,
                "realtime.tick_stale_after_seconds must be > 0 (got #{raw.inspect})"
        end

        value
      rescue ArgumentError, TypeError => e
        raise Errors::ConfigurationError,
              "realtime.tick_stale_after_seconds is unparseable (#{raw.inspect}): #{e.message}"
      end

      # Absent -> documented default. Explicit 0 -> 0 (throttle DISABLED —
      # the operator's explicit choice; it used to be silently converted
      # back to 0.25s, making the knob impossible to turn off). Negative or
      # unparseable raises.
      def realtime_min_enforcement_gap_seconds
        raw = realtime_config[:min_enforcement_gap_ms]
        return DEFAULT_MIN_ENFORCEMENT_GAP_SECONDS if raw.nil?

        ms = Float(raw)
        if ms.negative?
          raise Errors::ConfigurationError,
                "realtime.min_enforcement_gap_ms must be >= 0 (got #{raw.inspect})"
        end

        ms / 1000.0
      rescue ArgumentError, TypeError => e
        raise Errors::ConfigurationError,
              "realtime.min_enforcement_gap_ms is unparseable (#{raw.inspect}): #{e.message}"
      end
    end
  end
end
