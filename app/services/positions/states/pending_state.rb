# frozen_string_literal: true

module Positions
  module States
    # Position has been created and a broker order placed, but the fill has
    # not yet been confirmed by DhanHQ. Transitions to :active on fill or
    # :cancelled if the order is rejected / manually cancelled.
    class PendingState < BaseState
      def can_activate? = true

      def on_enter
        log('Entered PENDING — awaiting broker fill confirmation')
      end
    end
  end
end
