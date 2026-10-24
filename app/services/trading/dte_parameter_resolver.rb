# frozen_string_literal: true

module Trading
  # Maps DTE to intraday options-buying parameters (SL/TP/trail/volume window).
  # Merged into the position config snapshot at entry so exits stay pinned.
  #
  # Error-handling review 2026-09 (wave 2):
  #   * Feature is opt-in: risk.dte_parameters.enabled must be explicitly true.
  #     (Previously an absent section was treated as enabled.)
  #   * No blanket rescues: a corrupt config document propagates instead of
  #     silently degrading to "no DTE tuning".
  #   * volume_velocity_multiplier no longer falls back to a hardcoded 2.0 —
  #     when the feature is enabled the value must be configured (algo.yml
  #     ships defaults.volume_velocity_multiplier: 2.0).
  class DteParameterResolver
    class << self
      # @return [Hash] merged tier parameters; {} only when the feature is
      #   disabled (documented outcome)
      def resolve(dte:)
        return {} unless enabled?

        tier = tier_for(dte)
        defaults = config[:defaults] || {}
        merged = deep_symbolize(defaults).merge(deep_symbolize(tier))
        merged[:dte] = dte unless dte.nil?
        merged
      end

      def risk_overrides_for(dte:)
        params = resolve(dte: dte)
        return {} if params.empty?

        overrides = {}
        overrides[:sl_pct] = params[:sl_pct].to_f if params[:sl_pct]
        overrides[:tp_pct] = params[:tp_pct].to_f if params[:tp_pct]
        if params[:trail_pct]
          overrides[:trailing] = (overrides[:trailing] || {}).merge(drawdown_pct: params[:trail_pct].to_f)
        end
        overrides.compact
      end

      # @return [Float, nil] multiplier for the tier; nil when the feature is
      #   disabled (documented outcome — callers skip, they do not assume)
      # @raise [Errors::ConfigurationError] when enabled but the multiplier is
      #   not configured as a positive number
      def volume_velocity_multiplier(dte:)
        return nil unless enabled?

        params = resolve(dte: dte)
        raw = params[:volume_velocity_multiplier] || config.dig(:defaults, :volume_velocity_multiplier)
        value = raw.to_f

        unless raw.present? && value.finite? && value.positive?
          raise Errors::ConfigurationError,
                "risk.dte_parameters volume_velocity_multiplier must be a positive number " \
                "(tier for DTE=#{dte.inspect} or defaults) — got #{raw.inspect}"
        end

        value
      end

      def max_entry_time(dte:)
        params = resolve(dte: dte)
        params[:max_entry_time].presence
      end

      private

      def enabled?
        config[:enabled] == true
      end

      def config
        AlgoConfig.fetch.dig(:risk, :dte_parameters) || {}
      end

      # Tier hierarchy (explicit config design, not an error fallback):
      # by_dte["<dte>"] > by_dte["default"] > no tier params.
      def tier_for(dte)
        return config.dig(:by_dte, 'default') || {} if dte.nil?

        by_dte = config[:by_dte] || {}
        key = dte.to_i.clamp(0, 7).to_s
        by_dte[key] || by_dte['default'] || {}
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.deep_symbolize_keys
        else
          value
        end
      end
    end
  end
end
