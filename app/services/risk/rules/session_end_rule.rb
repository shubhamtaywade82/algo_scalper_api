# frozen_string_literal: true

module Risk
  module Rules
    # Rule that enforces session end exit (before 3:15 PM IST)
    # Highest priority - takes precedence over other rules
    class SessionEndRule < BaseRule
      PRIORITY = 10

      def evaluate(context)
        return skip_result unless context.active?

        session_check = TradingSession::Service.should_force_exit?
        return no_action_result unless session_check[:should_exit]

        exit_result(
          reason: 'session end (deadline: 3:15 PM IST)',
          metadata: { session_check: session_check }
        )
      end
    end
  end
end
