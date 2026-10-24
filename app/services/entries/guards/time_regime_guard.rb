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
          return true unless rules_enabled?

          regime_service = Live::TimeRegimeService.instance
          regime = regime_service.current_regime

          return false unless regime_service.allow_new_trades?
          return false unless regime_service.allow_entries?(regime)

          if (regime == Live::TimeRegimeService::CLOSE_GAMMA) && (Live::TimeRegimeService.instance.current_ist_time.strftime('%H:%M') >= '14:45')
            return false
          end

          true
        rescue Errors::Error => e
          # Domain failures (corrupt regime config, coverage gap) block —
          # fail-closed, same contract as the other wave-2/4 guards.
          Rails.logger.warn("[TimeRegimeGuard] blocking entry: time_regime_resolution_failed: #{e.class} - #{e.message}")
          false
        rescue StandardError => e
          # Unexpected failure inside the check itself: BLOCK, not pass. The
          # previous `rescue -> true` turned every crash of this check into
          # "entries allowed" — the exact assumption the error-handling
          # review exists to remove.
          Rails.logger.error("[TimeRegimeGuard] time_regime_allows_entry? error: #{e.class} - #{e.message}")
          false
        end

        # Delegates to the service (single source of truth). Section absent or
        # enabled: false -> false (documented "no regime rules" state); a
        # corrupt config document raises via AlgoConfig.fetch.
        def rules_enabled?
          Live::TimeRegimeService.instance.rules_enabled?
        end
      end
    end
  end
end
