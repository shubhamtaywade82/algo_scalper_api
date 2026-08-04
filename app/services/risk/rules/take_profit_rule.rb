# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces take profit limit
    # Triggers exit when PnL percentage exceeds configured take profit threshold
    class TakeProfitRule < BaseRule
      PRIORITY = 30

      def evaluate(context)
        return skip_result unless context.active?

        pnl_pct = context.tracker_snapshot&.dig(:pnl_pct) || context.position&.pnl_pct
        return skip_result if pnl_pct.nil?

        target = take_profit_threshold(context)
        return no_action_result unless target.positive? && pnl_pct.to_f >= target

        exit_result(
          reason: 'TAKE_PROFIT',
          metadata: {
            path: 'take_profit',
            pnl_pct: (pnl_pct.to_f * 100.0).round(2)
          }
        )
      end

      private

      def take_profit_threshold(context)
        cfg = Live::UnifiedExitChecker.send(:exit_config_for, context.tracker)
        cfg[:take_profit].to_f
      rescue StandardError
        context.risk_config[:tp_pct].to_f
      end
    end
  end
end
