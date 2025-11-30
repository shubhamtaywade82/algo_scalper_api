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

        sl_pct = context.config_bigdecimal(:sl_pct, BigDecimal('0'))
        return skip_result if sl_pct.zero?

        normalized_pct = pnl_pct.to_f / 100.0

        return no_action_result unless normalized_pct <= -sl_pct.to_f

        exit_result(
          reason: "SL HIT #{pnl_pct.round(2)}%",
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
