# frozen_string_literal: true

module Orders
  module Commands
    # Abstract base for all order Commands.
    #
    # Subclasses implement #execute and may override #validate.
    # Every invocation is wrapped in uniform structured logging so all
    # order activity has a consistent audit trail.
    #
    # Pattern highlights:
    #   • #call is the single public entry point (Template Method)
    #   • Validation is a separate step, returns nil to proceed or a failure result
    #   • Execution errors are caught and returned as CommandResult::failure
    #
    # Usage:
    #   class MyCommand < BaseCommand
    #     def execute
    #       # … perform work …
    #       success(order_id: "X")
    #     end
    #   end
    #
    #   result = MyCommand.new(gateway: gw, tracker: tracker).call
    #   result.success?  # => true
    class BaseCommand
      attr_reader :gateway, :tracker, :options

      def initialize(gateway:, tracker:, **options)
        @gateway = gateway
        @tracker = tracker
        @options = options
      end

      # Public entry point — validates, executes, logs, and returns a CommandResult.
      # @return [CommandResult]
      def call
        validation_failure = validate
        return validation_failure if validation_failure

        result = execute
        log_result(result)
        result
      rescue StandardError => e
        err = CommandResult.failure('command_exception', error: e, command_class: command_name)
        log_result(err)
        err
      end

      protected

      # Subclasses must implement this.
      # @return [CommandResult]
      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      # Optional pre-execution check. Return a CommandResult to abort, nil to proceed.
      # @return [CommandResult, nil]
      def validate
        return failure('missing_gateway') unless gateway
        return failure('missing_tracker') unless tracker

        nil
      end

      # ── Convenience builders (mirror CommandResult factory methods) ────────

      def success(payload = {})
        CommandResult.success(payload: payload, command_class: command_name)
      end

      def failure(reason, error: nil, payload: {})
        CommandResult.failure(reason, error: error, payload: payload, command_class: command_name)
      end

      def command_name
        self.class.name
      end

      private

      def log_result(result)
        order_no = tracker&.order_no || '(no tracker)'
        if result.success?
          Rails.logger.info(
            "[#{command_name}] #{order_no} → #{result.reason} payload=#{result.payload.inspect}"
          )
        else
          Rails.logger.error(
            "[#{command_name}] #{order_no} FAILED reason=#{result.reason} " \
            "error=#{result.error&.message}"
          )
        end
      end
    end
  end
end
