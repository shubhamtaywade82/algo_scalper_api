# frozen_string_literal: true

module Risk
  module Rules
    # Force-exits all active option positions when India VIX exceeds the accelerator threshold.
    class VixForceExitRule < BaseRule
      PRIORITY = 6

      def evaluate(context)
        return skip_result unless enabled?
        return skip_result unless context.active?
        return no_action_result unless Market::VixGate.force_exit_active?

        vix = Market::VixGate.current_ltp
        exit_result(
          reason: "VIX_FORCE_EXIT (India VIX=#{vix&.round(2) || 'n/a'})",
          metadata: {
            path: 'vix_force_exit',
            vix_ltp: vix
          }
        )
      end

      def enabled?(_context = nil)
        AlgoConfig.fetch.dig(:market, :vix_gate, :enabled) == true
      rescue StandardError
        false
      end
    end
  end
end
