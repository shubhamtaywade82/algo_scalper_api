# frozen_string_literal: true

module Risk
  module Rules
    # Rule that triggers an exit based on a specific time of day.
    # Matches logic from UnifiedExitChecker#time_based_exit?
    class TimeBasedExitRule < BaseRule
      def evaluate(context)
        tracker = context.tracker
        return skip_result unless tracker

        # Delegate to legacy method for parity and spec compatibility
        if Live::UnifiedExitChecker.time_based_exit?(tracker)
          return exit_result(
            reason: 'TIME_BASED',
            metadata: {
              path: 'time_based'
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[TimeBasedExitRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?(context)
        config_for_rule(context)[:enabled] == true
      end

      private

      def config_for_rule(context)
        cfg = context.risk_config.dig(:exit, :time_based) ||
              context.risk_config.dig(:risk, :time_based) || {}

        # Fallback to direct fetch if context is empty (legacy compat)
        if cfg.empty?
          cfg = AlgoConfig.fetch.dig(:exit, :time_based) || {}
        end
        cfg
      end
    end
  end
end
