# frozen_string_literal: true

module Ai
  module TradingAgent
    # Audit trail for tool calls, observations, risk checks, and final intents.
    # Stores structured trace data for debugging and learning.
    class TraceLogger
      Entry = Struct.new(:timestamp, :type, :name, :data, keyword_init: true)

      attr_reader :entries

      def initialize
        @entries = []
      end

      def log_tool_call(name, args)
        @entries << Entry.new(
          timestamp: Time.current,
          type: :tool_call,
          name: name,
          data: { arguments: args }
        )
      end

      def log_observation(name, summary)
        @entries << Entry.new(
          timestamp: Time.current,
          type: :observation,
          name: name,
          data: { summary: summary }
        )
      end

      def log_risk_check(checks)
        @entries << Entry.new(
          timestamp: Time.current,
          type: :risk_check,
          name: 'risk_validator',
          data: checks
        )
      end

      def log_intent(intent)
        @entries << Entry.new(
          timestamp: Time.current,
          type: :intent,
          name: 'final_intent',
          data: intent
        )
      end

      def log_error(error_message)
        @entries << Entry.new(
          timestamp: Time.current,
          type: :error,
          name: 'error',
          data: { message: error_message }
        )
      end

      def to_h
        {
          entries: @entries.map do |e|
            {
              timestamp: e.timestamp.iso8601,
              type: e.type,
              name: e.name,
              data: e.data
            }
          end,
          summary: build_summary
        }
      end

      private

      def build_summary
        tool_calls = @entries.count { |e| e.type == :tool_call }
        observations = @entries.count { |e| e.type == :observation }
        risk_checks = @entries.count { |e| e.type == :risk_check }
        errors = @entries.count { |e| e.type == :error }
        intent = @entries.find { |e| e.type == :intent }

        {
          total_entries: @entries.size,
          tool_calls: tool_calls,
          observations: observations,
          risk_checks: risk_checks,
          errors: errors,
          final_action: intent&.data&.dig(:action),
          duration_ms: duration_ms
        }
      end

      def duration_ms
        return 0 if @entries.size < 2

        ((@entries.last.timestamp - @entries.first.timestamp) * 1000).round(0)
      end
    end
  end
end
