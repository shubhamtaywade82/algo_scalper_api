# frozen_string_literal: true

module Entries
  module Guards
    class TimeRegimeGuard
      class << self
        def call(context)
          return EntryGuardPipeline::PASS if context[:expiry_power_trend]

          if time_regime_allows_entry?(context)
            return EntryGuardPipeline::PASS
          end

          { blocked: "time regime rules for #{context[:index_cfg][:key]}" }
        end

        private

        def time_regime_allows_entry?(context)
          return true unless time_regime_rules_enabled?

          regime_service = Live::TimeRegimeService.instance
          regime = regime_service.current_regime

          return false unless regime_service.allow_new_trades?
          return false unless regime_service.allow_entries?(regime)

          if regime == Live::TimeRegimeService::CLOSE_GAMMA && regime_service.current_ist_time.strftime('%H:%M') >= '14:45'
            return false
          end

          return false unless adx_within_regime_bounds?(regime_service.regime_config(regime), context)

          true
        rescue StandardError
          true
        end

        # Historical regime research (60+ trading days, 5m bars, NIFTY/BANKNIFTY/SENSEX) found
        # ADX has no clean "higher is better" line: within trend_continuation specifically,
        # very high ADX was consistently the WORST bucket (likely late/exhaustion moves), while
        # min_adx already guards the floor. `min_adx`/`max_adx` enforce global floor/ceiling;
        # `per_index_min_adx`/`per_index_max_adx` (optional, keyed by index symbol) override
        # them per index — BANKNIFTY's optimal cutoffs measured meaningfully different from
        # NIFTY/SENSEX (min 20 vs 15, max 40 vs 35), which were statistically indistinguishable
        # from each other and kept shared. All of this is only applied when the regime config
        # sets it AND the signal actually carries an ADX value — absent either, this is a no-op
        # (matches MiddayQualityGuard's pattern of not blocking on data it doesn't have).
        def adx_within_regime_bounds?(regime_cfg, context)
          adx = adx_value(context)
          return true if adx.nil?

          index_key = context.dig(:index_cfg, :key).to_s.upcase

          min = per_index_bound(regime_cfg, :per_index_min_adx, index_key) || regime_cfg[:min_adx]
          return false if min && adx < min.to_f

          max = per_index_bound(regime_cfg, :per_index_max_adx, index_key) || regime_cfg[:max_adx]
          return false if max && adx > max.to_f

          true
        end

        def per_index_bound(regime_cfg, key, index_key)
          overrides = regime_cfg[key] || {}
          overrides[index_key] || overrides[index_key.to_sym]
        end

        def adx_value(context)
          metadata = context[:entry_metadata] || {}
          value = context.dig(:pick, :adx_value) || metadata[:adx_value]
          value&.to_f
        end

        def time_regime_rules_enabled?
          AlgoConfig.fetch.dig(:risk, :time_regimes, :enabled) == true
        rescue StandardError
          false
        end
      end
    end
  end
end
