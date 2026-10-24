# frozen_string_literal: true

module Positions
  module States
    # Position has reached the trailing activation profit and the trailing
    # stop is now armed. ExitEngine / UnifiedExitChecker will fire if the
    # drawdown from the high-water-mark exceeds the configured threshold.
    class TrailingState < BaseState
      def can_trail?        = true
      def can_request_exit? = true
      def trailing_armed?   = true

      def on_enter
        log('Entered TRAILING — trailing stop armed, monitoring drawdown from HWM')
      end
    end
  end
end
