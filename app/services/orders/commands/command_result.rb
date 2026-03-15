# frozen_string_literal: true

module Orders
  module Commands
    # Immutable value object wrapping the outcome of a Command execution.
    #
    # Every Command returns one of these so callers always have a uniform
    # interface regardless of success or failure.
    #
    # Usage:
    #   result = CommandResult.success(payload: { order_id: "ABC" })
    #   result.success?          # => true
    #   result.payload[:order_id]# => "ABC"
    #
    #   result = CommandResult.failure("broker_rejected", error: e)
    #   result.failure?          # => true
    #   result.reason            # => "broker_rejected"
    #   result.error             # => #<RuntimeError …>
    class CommandResult
      attr_reader :success, :reason, :payload, :error, :executed_at, :command_class

      def initialize(success:, reason: nil, payload: {}, error: nil, command_class: nil)
        @success       = success
        @reason        = reason
        @payload       = payload || {}
        @error         = error
        @executed_at   = Time.current
        @command_class = command_class
      end

      # ── Factory helpers ────────────────────────────────────────────────────

      def self.success(reason: 'ok', payload: {}, command_class: nil)
        new(success: true, reason: reason, payload: payload, command_class: command_class)
      end

      def self.failure(reason, error: nil, payload: {}, command_class: nil)
        new(success: false, reason: reason, error: error, payload: payload, command_class: command_class)
      end

      # ── Predicates ─────────────────────────────────────────────────────────

      def success? = @success == true
      def failure? = !success?

      # ── Serialisation ──────────────────────────────────────────────────────

      def to_h
        {
          success: success,
          reason: reason,
          payload: payload,
          error: error&.message,
          executed_at: executed_at,
          command: command_class
        }
      end

      def inspect
        "#<CommandResult success=#{success} reason=#{reason.inspect} payload=#{payload.inspect}>"
      end
    end
  end
end
