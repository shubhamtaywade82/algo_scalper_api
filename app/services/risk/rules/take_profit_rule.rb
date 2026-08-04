# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces take profit limit
    # Triggers exit when PnL percentage exceeds configured take profit threshold
    class TakeProfitRule < BaseRule
      PRIORITY = 30

      def evaluate(context)
        return skip_result unless context.active?

        pnl_pct = context.pnl_pct
        return skip_result if pnl_pct.nil?

        tp_pct = context.config_bigdecimal(:tp_pct, BigDecimal(0))
        return skip_result if tp_pct.zero?

        # pnl_pct is stored as decimal (0.0573), tp_pct is also decimal (0.05)
        # Compare directly without conversion
        return no_action_result unless pnl_pct.to_f >= tp_pct.to_f

        # Convert to percentage for display
        pnl_pct_display = (pnl_pct.to_f * 100.0).round(2)
        exit_result(
          reason: "TP HIT #{pnl_pct_display}%",
          metadata: {
            pnl_pct: pnl_pct,
            tp_pct: tp_pct.to_f,
            normalized_pct: normalized_pct
          }
        )
      end
    end
  end
end
