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

        # Historical regime research (61 trading days, 5m bars, NIFTY/BANKNIFTY/SENSEX) found
        # ADX has no clean "higher is better" line: within trend_continuation specifically,
        # ADX >= 35 was consistently the WORST bucket (likely late/exhaustion moves), while
        # min_adx already guards the floor. `max_adx` (optional per regime) enforces that
        # ceiling; only applied when both the regime config sets it and the signal actually
        # carries an ADX value — absent either, this is a no-op (matches MiddayQualityGuard's
        # pattern of not blocking on data it doesn't have).
        def adx_within_regime_bounds?(regime_cfg, context)
          adx = adx_value(context)
          return true if adx.nil?

          min = regime_cfg[:min_adx]
          return false if min && adx < min.to_f

          max = regime_cfg[:max_adx]
          return false if max && adx > max.to_f

          true
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
