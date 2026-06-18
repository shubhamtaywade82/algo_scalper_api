# frozen_string_literal: true

module Trading
  # Maps DTE to intraday options-buying parameters (SL/TP/trail/volume window).
  # Merged into the position config snapshot at entry so exits stay pinned.
  class DteParameterResolver
    class << self
      def resolve(dte:)
        return {} unless enabled?

        tier = tier_for(dte)
        defaults = config[:defaults] || {}
        merged = deep_symbolize(defaults).merge(deep_symbolize(tier))
        merged[:dte] = dte unless dte.nil?
        merged
      rescue StandardError => e
        Rails.logger.warn("[DteParameterResolver] #{e.class} - #{e.message}")
        {}
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

      def volume_velocity_multiplier(dte:)
        params = resolve(dte: dte)
        (params[:volume_velocity_multiplier] || config.dig(:defaults, :volume_velocity_multiplier) || 2.0).to_f
      end

      def max_entry_time(dte:)
        params = resolve(dte: dte)
        params[:max_entry_time].presence
      end

      private

      def enabled?
        config[:enabled] != false
      end

      def config
        AlgoConfig.fetch.dig(:risk, :dte_parameters) || {}
      rescue StandardError
        {}
      end

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
