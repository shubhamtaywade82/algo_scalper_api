# frozen_string_literal: true

module Risk
  module Rules
    # Rule that uses Smart Money Concepts (SMC) via Navigator to identify liquidity-based exits.
    # Matches logic from UnifiedExitChecker#check_smc_navigator_exit
    class SmcNavigatorRule < BaseRule
      PRIORITY = 70 # Medium-low priority (context/structure-based)

      def evaluate(context)
        tracker = context.tracker
        snapshot = context.tracker_snapshot
        return skip_result unless tracker && snapshot

        # Delegate to legacy method for parity and spec compatibility
        result = Live::UnifiedExitChecker.check_smc_navigator_exit(tracker, snapshot)
        
        if result && result[:exit]
          return exit_result(
            reason: result[:reason] || 'SMC_NAVIGATOR_EXIT',
            metadata: {
              path: 'smc_navigator'
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[SmcNavigatorRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?(context = nil)
        # Delegate enabled check to the legacy checker's internal toggle
        smc_navigator_enabled?
      end

      private

      def smc_navigator_enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        cfg[:enabled] == true
      rescue StandardError
        false
      end

      def min_hold_elapsed?(tracker)
        return false unless tracker.created_at

        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        min_seconds = (cfg[:min_hold_seconds] || 120).to_i
        (Time.current - tracker.created_at) >= min_seconds
      rescue StandardError
        false
      end

      def min_confidence
        cfg = AlgoConfig.fetch.dig(:risk, :exits, :smc_navigator_exit) || {}
        (cfg[:min_confidence] || 0.65).to_f
      rescue StandardError
        0.65
      end
    end
  end
end
