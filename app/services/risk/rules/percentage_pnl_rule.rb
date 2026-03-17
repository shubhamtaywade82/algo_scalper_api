# frozen_string_literal: true

module Risk
  module Rules
    # Rule that triggers exit when PnL percentage reaches a specific threshold
    # Useful for full exit on % based pnl
    class PercentagePnlRule < BaseRule
      PRIORITY = 25 # Higher priority than TakeProfitRule (30)

      def evaluate(context)
        return skip_result unless context.active?

        pnl_pct = context.pnl_pct # DECIMAL format (e.g., 0.30 for 30%)
        return skip_result if pnl_pct.nil?

        # Get target from config (passed to rule on init)
        cfg = config[:percentage_pnl_exit] || {}
        target_pct = cfg[:target_pct]
        target_pct ||= config[:tp_pct] # Fallback to global TP if not specialized

        target_val = BigDecimal(target_pct.to_s)
        return skip_result if target_val.zero?

        # target_pct from config is now DECIMAL (e.g. 0.30 for 30%)
        # No conversion needed - use directly as threshold
        threshold = target_val

        # Hard minimum threshold to prevent tick-noise exits (e.g. must be at least 1% if target is 15%)
        return no_action_result if pnl_pct < 0.01 && threshold >= 0.05

        # CRITICAL: Only exit if target threshold is reached - this check ensures we don't exit prematurely
        return no_action_result unless pnl_pct >= threshold

        pnl_pct_display = (pnl_pct.to_f * 100.0).round(2)
        exit_result(
          reason: "PERCENTAGE_PNL_EXIT HIT #{pnl_pct_display}% (Target: #{(threshold.to_f * 100.0).round(2)}%)",
          metadata: {
            pnl_pct: pnl_pct.to_f,
            target_pct: threshold.to_f
          }
        )
      end
    end
  end
end
