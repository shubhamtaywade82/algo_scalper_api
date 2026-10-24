# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces take profit limit
    # Triggers exit when PnL percentage exceeds configured take profit threshold
    class TakeProfitRule < BaseRule
      PRIORITY = 30

      def evaluate(context)
        return skip_result unless context.active?

        if Live::UnifiedExitChecker.send(:profit_target_hit?, context.tracker, context.tracker_snapshot)
          pnl_pct = context.tracker_snapshot[:pnl_pct].to_f

          return exit_result(
            reason: 'TAKE_PROFIT',
            metadata: {
              path: 'take_profit',
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      end
    end
  end
end
