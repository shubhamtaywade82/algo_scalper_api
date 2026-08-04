# frozen_string_literal: true

module Entries
  module Guards
    class TimeRegimeGuard
      class << self
        def call(context)
          return EntryGuardPipeline::PASS if AlgoConfig.run_mode == 'exit_testing'
          return EntryGuardPipeline::PASS if context[:expiry_power_trend]

          if time_regime_allows_entry?(
            index_cfg: context[:index_cfg],
            pick: context[:pick],
            direction: context[:direction]
          )
            return EntryGuardPipeline::PASS
          end

          { blocked: "time regime rules for #{context[:index_cfg][:key]}" }
        end

        private

        def time_regime_allows_entry?(index_cfg:, pick:, direction:)
          return true unless time_regime_rules_enabled?

          regime_service = Live::TimeRegimeService.instance
          regime = regime_service.current_regime

          return false unless regime_service.allow_new_trades?
          return false unless regime_service.allow_entries?(regime)

          if regime == Live::TimeRegimeService::CLOSE_GAMMA
            return false if Live::TimeRegimeService.instance.current_ist_time.strftime('%H:%M') >= '14:45'
          end

          true
        rescue StandardError
          true
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
