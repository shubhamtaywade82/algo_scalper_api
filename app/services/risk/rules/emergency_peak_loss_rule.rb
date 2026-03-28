# frozen_string_literal: true

module Risk
  module Rules
    # Rule that triggers an emergency exit if a position was highly profitable
    # but has now flipped into a loss.
    # Matches logic from UnifiedExitChecker#emergency_peak_loss_exit_triggered?
    class EmergencyPeakLossRule < BaseRule
      PRIORITY = 5 # Very high priority (just below portfolio floor)

      def evaluate(context)
        tracker = context.tracker
        return skip_result unless tracker

        # Configuration (defaults to 10% peak profit requirement)
        drawdown_cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
        return no_action_result if drawdown_cfg[:emergency_peak_loss_exit] == false

        min_peak_pct = (drawdown_cfg[:emergency_min_peak_pct] || 0.10).to_f
        
        entry_price = tracker.entry_price.to_f
        quantity = tracker.quantity.to_i
        entry_value = entry_price * quantity
        return skip_result if entry_value <= 0

        # peak_pct is HWM PnL relative to entry value
        peak_pct = tracker.high_water_mark_pnl.to_f / entry_value
        current_pct = tracker.current_pnl_pct.to_f

        # Condition: Position reached >10% profit but is now >-2% loss
        if peak_pct >= min_peak_pct && current_pct < -0.02
          return exit_result(
            reason: 'EMERGENCY_PEAK_LOSS',
            metadata: {
              peak_pct: (peak_pct * 100.0).round(2),
              current_pct: (current_pct * 100.0).round(2)
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[EmergencyPeakLossRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?
        # Directly controlled by drawdown config in algo.yml
        cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
        cfg[:emergency_peak_loss_exit] != false
      end
    end
  end
end
