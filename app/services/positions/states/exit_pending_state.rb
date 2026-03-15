# frozen_string_literal: true

module Positions
  module States
    # An exit order has been dispatched to the broker but the fill confirmation
    # (via DhanHQ OrderUpdateHub WebSocket) has not yet arrived.
    # The position may not accept a second exit request.
    class ExitPendingState < BaseState
      def can_close? = true

      def on_enter
        log('Entered EXIT_PENDING — exit order dispatched, awaiting broker fill')
      end
    end
  end
end
