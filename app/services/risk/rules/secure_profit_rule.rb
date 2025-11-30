# frozen_string_literal: true

module Risk
  module Rules
    # Rule that secures profits above a threshold (e.g., ₹1000) while allowing positions to ride
    # Uses tighter peak drawdown protection when profit exceeds secure threshold
    # Designed for options trading where volatility can quickly reverse profits
    #
    # Strategy:
    # - When profit >= secure_profit_threshold (₹1000), activate tighter trailing protection
    # - Use tighter peak drawdown threshold (e.g., 3% instead of 5%)
    # - This allows positions to ride profits but protects against sudden reversals
    #
    # Example:
    # - Position reaches ₹1200 profit (peak)
    # - Current profit drops to ₹1100 (8.3% drawdown from peak)
    # - With 3% threshold: Exit triggered (protects ₹1100 profit)
    # - Without this rule: Position might ride to ₹1500 or drop to ₹500
    class SecureProfitRule < BaseRule
      PRIORITY = 35 # Between TakeProfitRule (30) and TimeBasedExitRule (40)

      def evaluate(context)
        return skip_result unless context.active?

        pnl_rupees = context.pnl_rupees
        return skip_result unless pnl_rupees&.positive?

        secure_profit_threshold = context.config_bigdecimal(:secure_profit_threshold_rupees, BigDecimal('1000'))
        return skip_result if secure_profit_threshold.zero?

        # Only activate when profit exceeds secure threshold
        return no_action_result unless BigDecimal(pnl_rupees.to_s) >= secure_profit_threshold

        # Check peak drawdown with tighter threshold
        peak_profit_pct = context.peak_profit_pct
        current_profit_pct = context.pnl_pct
        return skip_result unless peak_profit_pct && current_profit_pct

        # Use tighter drawdown threshold when profit is secured
        tight_drawdown_pct = context.config_bigdecimal(:secure_profit_drawdown_pct, BigDecimal('3.0'))
        drawdown = peak_profit_pct - current_profit_pct

        return no_action_result unless drawdown >= tight_drawdown_pct.to_f

        # Log the secure profit exit
        Rails.logger.info(
          "[SecureProfitRule] Securing profit for #{context.tracker.order_no}: " \
          "current=₹#{pnl_rupees.round(2)}, peak=#{peak_profit_pct.round(2)}%, " \
          "drawdown=#{drawdown.round(2)}%"
        )

        exit_result(
          reason: "secure_profit_exit (profit: ₹#{pnl_rupees.round(2)}, drawdown: #{drawdown.round(2)}% from peak #{peak_profit_pct.round(2)}%)",
          metadata: {
            pnl_rupees: pnl_rupees.to_f,
            peak_profit_pct: peak_profit_pct,
            current_profit_pct: current_profit_pct,
            drawdown: drawdown,
            tight_drawdown_pct: tight_drawdown_pct.to_f,
            secure_profit_threshold: secure_profit_threshold.to_f
          }
        )
      end
    end
  end
end
