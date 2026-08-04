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

        # pnl_pct is stored as decimal (0.0573), tp_pct is also decimal (0.05)
        # Compare directly without conversion
        return no_action_result unless pnl_pct.to_f >= tp_pct.to_f

        # Convert to percentage for display
        pnl_pct_display = (pnl_pct.to_f * 100.0).round(2)
        exit_result(
          reason: "TP HIT #{pnl_pct_display}%",
          metadata: {
            pnl_pct: pnl_pct,
            tp_pct: tp_pct.to_f
          }
        )
      end
    end
  end
end
