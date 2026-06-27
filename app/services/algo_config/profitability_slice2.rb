# frozen_string_literal: true

class AlgoConfig
  # Profitability Slice 2 — session discipline via DB document (no YAML edit required at runtime).
  class ProfitabilitySlice2
    APPLY_PATCH = {
      trading_time_restrictions: {
        enabled: true,
        avoid_periods: ['11:00-13:45'],
        block_exits: false
      },
      signals: {
        signal_tier: 'selective'
      }
    }.freeze

    ROLLBACK_PATCH = {
      trading_time_restrictions: {
        enabled: false,
        block_exits: false
      },
      signals: {
        signal_tier: 'exploratory'
      }
    }.freeze

    class << self
      def apply!(actor: 'rake')
        DocumentStore.apply_deep_merge_patch!(
          APPLY_PATCH,
          source: 'profitability_slice2_apply',
          actor: actor,
          metadata: { slice: 2, action: 'apply' }
        )
      end

      def rollback!(actor: 'rake')
        DocumentStore.apply_deep_merge_patch!(
          ROLLBACK_PATCH,
          source: 'profitability_slice2_rollback',
          actor: actor,
          metadata: { slice: 2, action: 'rollback' }
        )
      end

      def status
        config = AlgoConfig.fetch
        restrictions = config[:trading_time_restrictions] || {}
        {
          trading_time_restrictions_enabled: restrictions[:enabled] == true,
          avoid_periods: Array(restrictions[:avoid_periods]),
          signal_tier: config.dig(:signals, :signal_tier)
        }
      end
    end
  end
end
