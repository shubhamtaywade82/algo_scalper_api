# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces time-based exit
    # Triggers exit at configured time if minimum profit threshold is met
    class TimeBasedExitRule < BaseRule
      PRIORITY = 40

      def evaluate(context)
        return skip_result unless context.active?

        exit_time = context.config_time(:time_exit_hhmm, nil)
        return skip_result unless exit_time

        now = context.current_time
        return no_action_result unless now >= exit_time

        market_close_time = context.config_time(:market_close_hhmm, nil)
        return no_action_result if market_close_time && now >= market_close_time

        # Check minimum profit requirement
        pnl_rupees = context.pnl_rupees
        if pnl_rupees.to_f.positive?
          min_profit = context.config_bigdecimal(:min_profit_rupees, BigDecimal('0'))
          if min_profit.positive? && BigDecimal(pnl_rupees.to_s) < min_profit
            Rails.logger.info(
              "[TimeBasedExitRule] Time-based exit skipped for #{context.tracker.order_no} - PnL < min_profit"
            )
            return no_action_result
          end
        end

        exit_result(
          reason: "time-based exit (#{exit_time.strftime('%H:%M')})",
          metadata: {
            exit_time: exit_time,
            current_time: now,
            pnl_rupees: pnl_rupees
          }
        )
      end
    end
  end
end
