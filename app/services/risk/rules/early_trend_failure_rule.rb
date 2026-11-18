# frozen_string_literal: true

module Risk
  module Rules
    # Rule for detection of early trend failure before profit target is reached.
    # Matches logic from UnifiedExitChecker#early_exit_triggered?
    class EarlyTrendFailureRule < BaseRule
      PRIORITY = 10 # High priority but below emergency logic

      def evaluate(context)
        tracker = context.tracker
        snapshot = context.tracker_snapshot
        return skip_result unless tracker && snapshot

        # Delegate to legacy method for parity and spec compatibility
        if Live::UnifiedExitChecker.early_exit_triggered?(tracker, snapshot)
          return exit_result(
            reason: 'EARLY_TREND_FAILURE',
            metadata: {
              path: 'early_exit'
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[EarlyTrendFailureRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?(context = nil)
        # Always enabled if the system config allows it, but context-aware
        config.fetch(:enabled, true)
      end
    end
  end
end
