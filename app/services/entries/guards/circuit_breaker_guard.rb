# frozen_string_literal: true

module Entries
  module Guards
    class CircuitBreakerGuard
      class << self
        def call(context)
          return { blocked: block_reason } if Risk::CircuitBreaker.instance.tripped?

          EntryGuardPipeline::PASS
        end

        private

        def block_reason
          cb = Risk::CircuitBreaker.instance.status
          "circuit breaker tripped: #{cb[:reason]} (at: #{cb[:at]})"
        end
      end
    end
  end
end
