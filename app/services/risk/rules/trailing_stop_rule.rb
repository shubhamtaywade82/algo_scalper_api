# frozen_string_literal: true

module Risk
  module Rules
    # Rule that evaluates trailing stops including underlying context awareness
    class TrailingStopRule < BaseRule
      PRIORITY = 50

      def evaluate(context)
        return skip_result unless context.active?

        tracker = context.tracker
        snapshot = context.tracker_snapshot
        pnl_pct = snapshot[:pnl_pct].to_f

        # First evaluate underlying context (tightens or exits trailing stop)
        underlying_ctx = Live::UnifiedExitChecker.send(:evaluate_underlying_context, tracker, snapshot)

        if underlying_ctx[:action] == :exit
          return exit_result(
            reason: underlying_ctx[:reason],
            metadata: {
              path: 'underlying_context_exit',
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        # Then evaluate actual trailing stop with multiplier
        if Live::UnifiedExitChecker.send(:trailing_stop_hit?, tracker, snapshot, tightening_multiplier: underlying_ctx[:multiplier])
          return exit_result(
            reason: 'TRAILING_STOP',
            metadata: {
              path: 'trailing_stop',
              pnl_pct: (pnl_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      end
    end
  end
end
