# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces stop loss limit
    # Triggers exit when PnL percentage drops below configured stop loss threshold
    class StopLossRule < BaseRule
      PRIORITY = 20

      def evaluate(context)
        return skip_result unless context.active?

        pnl_pct = context.pnl_pct
        return skip_result if pnl_pct.nil?

        sl_pct = context.config_bigdecimal(:sl_pct, BigDecimal(0))
        return skip_result if sl_pct.zero?

        # pnl_pct is stored as decimal (0.0573), sl_pct is also decimal (0.03)
        # Compare directly without conversion
        return no_action_result unless pnl_pct.to_f <= -sl_pct.to_f

        # Convert to percentage for display
        pnl_pct_display = (pnl_pct.to_f * 100.0).round(2)
        exit_result(
          reason: "SL HIT #{pnl_pct_display}%",
          metadata: {
            pnl_pct: pnl_pct,
            sl_pct: sl_pct.to_f,
            normalized_pct: normalized_pct
          }
        )
      end
    end
  end
end
