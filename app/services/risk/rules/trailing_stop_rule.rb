# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces trailing stop based on high water mark drop (legacy method)
    # Triggers exit when PnL drops by configured percentage from high water mark
    # NOTE: This is a legacy trailing stop method. PeakDrawdownRule is preferred for new implementations.
    class TrailingStopRule < BaseRule
      PRIORITY = 50

      def evaluate(context)
        return skip_result unless context.active?

        pnl = context.pnl_rupees
        hwm = context.high_water_mark
        return skip_result if pnl.nil? || hwm.nil? || hwm.zero?

        drop_threshold = context.config_bigdecimal(:exit_drop_pct, BigDecimal(0))
        return skip_result if drop_threshold.zero?

        drop_pct = (hwm - pnl) / hwm
        return no_action_result unless drop_pct >= drop_threshold.to_f

        exit_result(
          reason: "TRAILING STOP drop=#{drop_pct.round(3)}",
          metadata: {
            pnl: pnl,
            hwm: hwm,
            drop_pct: drop_pct.to_f,
            drop_threshold: drop_threshold.to_f
          }
        )
      end
    end
  end
end
