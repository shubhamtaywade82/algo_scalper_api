# frozen_string_literal: true

module Risk
  module Rules
    # Rule that uses Smart Money Concepts (SMC) via Navigator to identify liquidity-based exits.
    # Matches logic from UnifiedExitChecker#check_smc_navigator_exit
    class SmcNavigatorRule < BaseRule
      PRIORITY = 70 # Medium-low priority (context/structure-based)

      def evaluate(context)
        tracker = context.tracker
        return skip_result unless tracker

        # snapshot ltp is needed
        ltp = context.position.current_ltp.to_f
        return no_action_result unless ltp.positive?

        # Gating: Enabled? and Min Hold Time?
        return no_action_result unless smc_navigator_enabled?
        return no_action_result unless min_hold_elapsed?(tracker)

        instrument = tracker.instrument
        return skip_result unless instrument

        # Run SMC Navigator analysis
        result = Smc::Navigator.evaluate_exit(tracker: tracker, ltp: ltp, instrument: instrument)
        
        # Check if exit is suggested and confidence meets threshold
        if result.suggest_exit? && result.confidence >= min_confidence
          return exit_result(
            reason: "SMC_NAVIGATOR_EXIT (#{result.reason})",
            metadata: {
              confidence: result.confidence.round(2),
              path: 'smc_navigator'
            }
          )
        end

        no_action_result
      rescue StandardError => e
        Rails.logger.error("[SmcNavigatorRule] Evaluation failed: #{e.message}")
        no_action_result
      end

      def enabled?
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
