# frozen_string_literal: true

module Live
  class RiskManagerService
    module Config
      private

      def risk_config
        raw = begin
          resolved_risk_config
        rescue StandardError
          {}
        end
        return {} if raw.blank?

        cfg = raw.dup
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
      rescue StandardError => e
        Rails.logger.error("[RiskManager] risk_config error: #{e.class} - #{e.message}")
        {}
      end

      # Merge exit-related config from the legacy location (:position_sizing) and the canonical location (:risk).
      # Canonical (:risk) wins on conflicts.
      def resolved_risk_config
        cfg = AlgoConfig.fetch
        legacy = cfg[:position_sizing].is_a?(Hash) ? cfg[:position_sizing] : {}
        risk = cfg[:risk].is_a?(Hash) ? cfg[:risk] : {}
        legacy.merge(risk)
      rescue StandardError
        {}
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
        AlgoConfig.fetch.dig(:risk, :hard_rupee_sl)
      rescue StandardError
        nil
      end

      def hard_rupee_tp_config
        AlgoConfig.fetch.dig(:risk, :hard_rupee_tp)
      rescue StandardError
        nil
      end

      def profit_floor_config
        raw = begin
          AlgoConfig.fetch.dig(:risk, :profit_floor) || {}
        rescue StandardError
          {}
        end

        {
          enabled: raw[:enabled] == true,
          lock_rupees: integer_or_nil(raw[:lock_rupees]),
          breakeven_at: integer_or_nil(raw[:breakeven_at]),
          time_kill_minutes: integer_or_nil(raw[:time_kill_minutes])
        }
      end

      def integer_or_nil(value)
        return nil if value.nil?

        Integer(value)
      rescue StandardError
        nil
      end

      def safe_big_decimal(value)
        return nil if value.nil?

        BigDecimal(value.to_s)
      rescue StandardError
        nil
      end

      def post_profit_zone_enabled?
        cfg = post_profit_zone_config
        cfg && cfg[:enabled] != false
      end

      def post_profit_zone_config
        raw = begin
          AlgoConfig.fetch.dig(:risk, :post_profit_zone) || {}
        rescue StandardError
          {}
        end

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
        config = begin
          AlgoConfig.fetch.dig(:risk, :time_overrides, :iv_collapse) || {}
        rescue StandardError
          {}
        end
        config[:enabled] == true
      end

      def stall_detection_enabled?
        config = stall_detection_config
        config[:enabled] == true
      end

      def stall_detection_config
        AlgoConfig.fetch.dig(:risk, :time_overrides, :stall_detection) || {}
      rescue StandardError
        {}
      end

      # Configuration helpers for new 5-layer exit system

      def structure_invalidation_enabled?
        config = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}
        config.fetch(:enabled, true) # Default: enabled
      rescue StandardError
        true
      end

      def premium_momentum_failure_enabled?
        config = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}
        config.fetch(:enabled, true) # Default: enabled
      rescue StandardError
        true
      end

      def time_stop_enabled?
        config = AlgoConfig.fetch.dig(:risk, :exits, :time_stop) || {}
        config.fetch(:enabled, true) # Default: enabled
      rescue StandardError
        true
      end

      def pct_value(value)
        BigDecimal(value.to_s)
      rescue StandardError
        BigDecimal(0)
      end
    end
  end
end
