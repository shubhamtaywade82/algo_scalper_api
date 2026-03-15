# frozen_string_literal: true

module Positions
  module States
    # Position is live and being monitored by RiskManagerService every tick.
    # Trailing stop is not yet armed. Transitions to :trailing once the
    # activation profit threshold is crossed, or directly to :exit_pending
    # if a hard stop or take-profit fires first.
    class ActiveState < BaseState
      def can_trail?        = true
      def can_request_exit? = true

      def on_enter
        log('Entered ACTIVE — monitoring for exit conditions')
      end
    end
  end
end
