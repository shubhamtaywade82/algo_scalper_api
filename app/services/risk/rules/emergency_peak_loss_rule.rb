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

        # Delegate to legacy method for parity and spec compatibility
        if Live::UnifiedExitChecker.emergency_peak_loss_exit_triggered?(tracker)
          return exit_result(
            reason: 'EMERGENCY_PEAK_LOSS',
            metadata: {
              path: 'emergency_peak_loss'
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[EmergencyPeakLossRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?(context = nil)
        # Delegate configuration logic natively or through UnifiedExitChecker
        cfg = AlgoConfig.fetch.dig(:position_sizing, :drawdown) || {}
        cfg[:emergency_peak_loss_exit] != false
      end
    end
  end
end
