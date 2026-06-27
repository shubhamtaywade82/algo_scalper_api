# frozen_string_literal: true

module Ai
  # Bridges MCP tool calls into the Ollama function-calling flow.
  #
  # This uses the local `dhanhq-mcp` adapter for validated DhanHQ tool specs
  # and routing, while keeping auth, risk, and execution controlled by the
  # Rails app and its existing Dhan integration.
  class DhanToolBridge
    class << self
      def context
        @context ||= Dhanhq::Mcp::Context.new(client: dhanhq_client)
      end

      def dhanhq_client
        @dhanhq_client ||= DhanHQ::Client.new(api_type: :option_chain)
      end

      def tools_for_ollama
        Dhanhq::Mcp::TOOL_SPEC.filter_map do |tool|
          {
            type: "function",
            function: {
              name: tool[:name],
              description: tool[:description],
              parameters: tool[:input_schema]
            }
          }
        end
      end

      def call(tool_name, arguments = {})
        validated_args = arguments.is_a?(Hash) ? arguments : {}

        result = Dhanhq::Mcp::Router.call(
          tool_name,
          validated_args,
          context
        )

        { tool_name => result }
      rescue Dhanhq::Mcp::Errors::UnknownTool => e
        { error: "unknown_tool", tool_name: tool_name, message: e.message }
      rescue StandardError => e
        { error: "tool_call_failed", tool_name: tool_name, message: e.message }
      end

      def reset!
        @context = nil
        @dhanhq_client = nil
      end
    end
  end
end
