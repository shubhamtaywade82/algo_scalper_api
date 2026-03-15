# frozen_string_literal: true

module Positions
  module States
    # Terminal state — position is fully closed (either exited with a fill
    # or cancelled before a fill). No further transitions are allowed.
    class ClosedState < BaseState
      def terminal? = true

      def on_enter
        log("Entered CLOSED — reason: #{tracker&.exit_reason || tracker&.status}")
      end
    end
  end
end
