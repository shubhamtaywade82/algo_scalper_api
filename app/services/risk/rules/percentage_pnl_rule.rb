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
        cfg = (config[:percentage_pnl_exit] || {})
        target_pct = cfg[:target_pct]
        target_pct ||= config[:tp_pct] # Fallback to global TP if not specialized

        target_val = BigDecimal(target_pct.to_s)
        return skip_result if target_val.zero?

        # pnl_pct is stored as decimal (e.g. 0.05), target_val may be percentage (e.g. 5.0) or decimal
        # We assume config values are decimal if < 1.0, else percentage
        # normalize_pct helper handles this in some contexts, but let's be explicit here
        threshold = target_val > 1.0 ? (target_val / 100.0) : target_val

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
