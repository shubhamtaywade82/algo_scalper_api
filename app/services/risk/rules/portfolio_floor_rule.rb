# frozen_string_literal: true

module Risk
  module Rules
    # Highest priority rule that triggers an exit for all positions
    # if the global portfolio profit floor has been breached.
    # Matches logic from UnifiedExitChecker#portfolio_floor_breach?
    class PortfolioFloorRule < BaseRule
      PRIORITY = 0 # Highest priority - overrides all other logic

      def evaluate(context)
        # Delegate to legacy method for parity and spec compatibility
        if Live::UnifiedExitChecker.portfolio_floor_breach?
          return exit_result(
            reason: 'PORTFOLIO_FLOOR_BREACH',
            metadata: {
              source: 'Portfolio::DrawdownGuard',
              path: 'profit_lock'
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PortfolioFloorRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?(context = nil)
        # Always enabled if the guard is active
        true
      end
    end
  end
end
