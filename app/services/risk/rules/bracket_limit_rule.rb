# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces bracket limits (SL/TP) from position data
    # This is a fallback check for positions that have bracket limits set
    class BracketLimitRule < BaseRule
      PRIORITY = 25

      def evaluate(context)
        return skip_result unless context.active?

        # Only check if position has current LTP
        return skip_result unless context.current_ltp&.positive?

        # Check if position has SL/TP hit flags
        if context.position.respond_to?(:sl_hit?) && context.position.sl_hit?
          return exit_result(
            reason: format('SL HIT %.2f%%', context.pnl_pct.to_f),
            metadata: { pnl_pct: context.pnl_pct, limit_type: 'stop_loss' }
          )
        end

        if context.position.respond_to?(:tp_hit?) && context.position.tp_hit?
          return exit_result(
            reason: format('TP HIT %.2f%%', context.pnl_pct.to_f),
            metadata: { pnl_pct: context.pnl_pct, limit_type: 'take_profit' }
          )
        end

        no_action_result
      end
    end
  end
end
