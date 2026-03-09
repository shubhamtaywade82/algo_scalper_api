# frozen_string_literal: true

module Risk
  module Rules
    # Rule that triggers exit when PnL percentage reaches a specific threshold
    # Useful for full exit on % based pnl
    class PercentagePnlRule < BaseRule
      PRIORITY = 25 # Higher priority than TakeProfitRule (30)

      def evaluate(context)
        return skip_result unless context.active?

        pnl_pct = context.pnl_pct
        return skip_result if pnl_pct.nil?

        # Get target from config (passed to rule on init)
        cfg = config[:percentage_pnl_exit] || {}
        target_pct = cfg[:target_pct]
        target_pct ||= config[:tp_pct] # Fallback to global TP if not specialized

        target_val = BigDecimal(target_pct.to_s)
        return skip_result if target_val.zero?

        # target_pct from config is expected to be a percentage (e.g. 15.0 for 15%)
        # Convert to decimal threshold (e.g. 0.15)
        # Handle cases where it might already be decimal or very small percentage
        threshold = if target_val > 1.0
                      target_val / 100.0
                    elsif target_val > 0.0 && target_val < 0.1 # likely a decimal like 0.05
                      target_val
                    else
                      target_val / 100.0 # assume percentage for everything else (e.g. 0.5%)
                    end

        # Hard minimum threshold to prevent tick-noise exits (e.g. must be at least 1% if target is 15%)
        return no_action_result if pnl_pct < 0.01 && threshold >= 0.05

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
