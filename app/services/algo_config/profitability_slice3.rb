# frozen_string_literal: true

class AlgoConfig
  # Profitability Slice 3 — pause SENSEX via index trade_limits (DB document patch).
  class ProfitabilitySlice3
    SENSEX_KEY = 'SENSEX'
    DEFAULT_SENSEX_MAX_TRADES = 2

    APPLY_PATCH = {
      indices: [
        {
          key: SENSEX_KEY,
          trade_limits: { max_trades_per_day: 0 }
        }
      ]
    }.freeze

    class << self
      def apply!(actor: 'rake')
        DocumentStore.apply_deep_merge_patch!(
          APPLY_PATCH,
          source: 'profitability_slice3_apply',
          actor: actor,
          metadata: { slice: 3, action: 'apply' }
        )
      end

      def rollback!(actor: 'rake', restore_max_trades: DEFAULT_SENSEX_MAX_TRADES)
        DocumentStore.apply_deep_merge_patch!(
          rollback_patch(restore_max_trades),
          source: 'profitability_slice3_rollback',
          actor: actor,
          metadata: { slice: 3, action: 'rollback' }
        )
      end

      def status
        sensex_cfg = sensex_index_config
        max_trades = sensex_cfg&.dig(:trade_limits, :max_trades_per_day)
        {
          sensex_max_trades_per_day: max_trades,
          sensex_paused: max_trades.to_i.zero?
        }
      end

      private

      def rollback_patch(restore_max_trades)
        {
          indices: [
            {
              key: SENSEX_KEY,
              trade_limits: { max_trades_per_day: restore_max_trades }
            }
          ]
        }
      end

      def sensex_index_config
        indices = AlgoConfig.fetch[:indices] || []
        indices.find { |idx| idx[:key].to_s.upcase == SENSEX_KEY }
      end
    end
  end
end
