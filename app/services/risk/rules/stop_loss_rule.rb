# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces stop loss limit
    # Triggers exit when PnL percentage drops below configured stop loss threshold
    class StopLossRule < BaseRule
      PRIORITY = 20

      def evaluate(context)
        return skip_result unless context.active?

        if Live::UnifiedExitChecker.send(:loss_limit_hit?, context.tracker, context.tracker_snapshot)
          pnl_pct = context.tracker_snapshot[:pnl_pct].to_f

          return exit_result(
            reason: 'STOP_LOSS', # Legacy checker mapped loss_limit_hit? to STOP_LOSS
            metadata: {
              path: 'stop_loss',
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      end
    end
  end
end
