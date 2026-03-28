# frozen_string_literal: true

module Risk
  module Rules
    # Premium Momentum Failure Rule - CRITICAL EXIT for intraday options buying
    #
    # PURPOSE: Kill dead option trades before theta eats them
    #
    # Logic: Track last premium high. Exit when premium does NOT make
    # progress within N minutes (configurable per index and session).
    #
    # Only fires on losing positions. Winners are handled by trailing.
    #
    # Priority: 30 (checked after structure invalidation)
    class PremiumMomentumFailureRule < BaseRule
      include SessionDetector

      PRIORITY = 30
      DEFAULT_STALL_MINUTES = 3

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?

        if Live::UnifiedExitChecker.premium_momentum_failure_hit?(context.tracker, context.tracker_snapshot)
          return exit_result(
            reason: 'PREMIUM_MOMENTUM_FAILURE',
            metadata: { path: 'premium_momentum_failure' }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[PremiumMomentumFailureRule] Error: #{e.class} - #{e.message}")
        skip_result
      end

      def enabled?(context = nil)
        pmf_cfg = config.dig(:risk, :exits, :premium_momentum_failure) || {}
        pmf_cfg[:enabled] == true
      end
    end
  end
end
