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

        tp_pct = context.config_bigdecimal(:tp_pct, BigDecimal('0'))
        return skip_result if tp_pct.zero?

        normalized_pct = pnl_pct.to_f / 100.0

        return no_action_result unless normalized_pct >= tp_pct.to_f

        exit_result(
          reason: "TP HIT #{pnl_pct.round(2)}%",
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
