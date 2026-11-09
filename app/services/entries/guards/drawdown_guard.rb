# frozen_string_literal: true

module Entries
  module Guards
    class DrawdownGuard
      include BaseGuard

      def self.call(context)
        if Portfolio::DrawdownGuard.triggered?(fail_closed: true)
          { blocked: 'drawdown_guard_active' }
        else
          PASS
        end
      end
    end
  end
end
