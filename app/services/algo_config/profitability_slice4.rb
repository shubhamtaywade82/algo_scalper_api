# frozen_string_literal: true

class AlgoConfig
  # Profitability Slice 4 — tighten catastrophic exit (adaptive_trail hard_stop + sl_pct).
  class ProfitabilitySlice4
    ENTRY_GUARD_STAGE = {
      name: 'entry_guard',
      min_profit: 0.0,
      trail_behind_peak: 0.40,
      hard_stop: -0.08
    }.freeze

    OTHER_STAGES = [
      { name: 'momentum_ride', min_profit: 0.20, trail_behind_peak: 0.35, hard_stop: nil },
      { name: 'profit_lock', min_profit: 0.60, trail_behind_peak: 0.28, hard_stop: nil },
      { name: 'runner_mode', min_profit: 1.20, trail_behind_peak: 0.22, hard_stop: nil }
    ].freeze

    TIGHTENED_STAGES = [ENTRY_GUARD_STAGE, *OTHER_STAGES].freeze

    ROLLBACK_ENTRY_GUARD = ENTRY_GUARD_STAGE.merge(hard_stop: -0.30).freeze
    ROLLBACK_STAGES = [ROLLBACK_ENTRY_GUARD, *OTHER_STAGES].freeze

    APPLY_PATCH = {
      risk: {
        sl_pct: 0.08,
        adaptive_trailing: { stages: TIGHTENED_STAGES }
      }
    }.freeze

    ROLLBACK_PATCH = {
      risk: {
        sl_pct: 0.10,
        adaptive_trailing: { stages: ROLLBACK_STAGES }
      }
    }.freeze

    class << self
      def apply!(actor: 'rake')
        DocumentStore.apply_deep_merge_patch!(
          APPLY_PATCH,
          source: 'profitability_slice4_apply',
          actor: actor,
          metadata: { slice: 4, action: 'apply' }
        )
      end

      def rollback!(actor: 'rake')
        DocumentStore.apply_deep_merge_patch!(
          ROLLBACK_PATCH,
          source: 'profitability_slice4_rollback',
          actor: actor,
          metadata: { slice: 4, action: 'rollback' }
        )
      end

      def status
        config = AlgoConfig.fetch
        entry_guard = entry_guard_stage(config)
        {
          sl_pct: config.dig(:risk, :sl_pct),
          entry_guard_hard_stop: entry_guard&.dig(:hard_stop)
        }
      end

      private

      def entry_guard_stage(config)
        stages = config.dig(:risk, :adaptive_trailing, :stages) || []
        stages.map(&:deep_symbolize_keys).find { |stage| stage[:name].to_s == 'entry_guard' }
      end
    end
  end
end
