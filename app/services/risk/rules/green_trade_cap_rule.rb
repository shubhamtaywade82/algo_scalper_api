# frozen_string_literal: true

module Risk
  module Rules
    # Caps max adverse move once a trade has been meaningfully green.
    # Prevents intraday options give-back from riding a full -15% premium SL.
    class GreenTradeCapRule < BaseRule
      PRIORITY = 19

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        cfg = rule_config
        min_hwm = cfg[:min_hwm_rupees].to_f
        max_adverse_pct = cfg[:max_adverse_pct].to_f
        return skip_result unless min_hwm.positive? && max_adverse_pct.positive?

        hwm_rupees = hwm_rupees_for(context)
        return no_action_result unless hwm_rupees.to_f >= min_hwm

        current_pct = context.pnl_pct.to_f
        return no_action_result unless current_pct <= -max_adverse_pct

        exit_result(
          reason: "GREEN_TRADE_CAP (hwm: ₹#{hwm_rupees.round(2)}, now: #{(current_pct * 100).round(2)}%, " \
                  "cap: -#{(max_adverse_pct * 100).round(1)}%)",
          metadata: {
            path: 'green_trade_cap',
            hwm_rupees: hwm_rupees.to_f,
            current_pnl_pct: current_pct,
            max_adverse_pct: max_adverse_pct
          }
        )
      end

      def enabled?(_context = nil)
        rule_config.fetch(:enabled, true) != false
      end

      private

      def rule_config
        AlgoConfig.fetch.dig(:risk, :green_trade_cap) || {}
      rescue StandardError
        {}
      end

      def hwm_rupees_for(context)
        snapshot = context.tracker_snapshot
        return snapshot[:hwm_pnl] if snapshot.is_a?(Hash) && snapshot[:hwm_pnl]

        context.high_water_mark || context.tracker&.high_water_mark_pnl
      end
    end
  end
end
