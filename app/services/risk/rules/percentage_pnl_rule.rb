# frozen_string_literal: true

module Risk
  module Rules
    # Rule that triggers exit when PnL percentage reaches a specific threshold
    # Useful for full exit on % based pnl
    class PercentagePnlRule < BaseRule
      PRIORITY = 25 # Higher priority than TakeProfitRule (30)

      def evaluate(context)
        return skip_result unless context.active?

        snapshot = context.tracker_snapshot || Live::RedisPnlCache.instance.fetch_pnl(context.tracker.id)
        return no_action_result if snapshot.nil?

        if Live::UnifiedExitChecker.send(:percentage_pnl_exit_hit?, context.tracker, snapshot)
          pnl_pct = snapshot[:pnl_pct].to_f

          return exit_result(
            reason: "PERCENTAGE_PNL_EXIT (#{(pnl_pct * 100.0).round(2)}%)",
            metadata: {
              path: 'percentage_pnl_exit',
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      end
    end
  end
end
