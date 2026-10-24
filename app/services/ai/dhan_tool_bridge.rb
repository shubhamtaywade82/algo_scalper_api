# frozen_string_literal: true

module Ai
  # Bridges MCP tool calls into the Ollama function-calling flow.
  #
  # This uses the local `dhanhq-mcp` adapter for validated DhanHQ tool specs
  # and routing, while keeping auth, risk, and execution controlled by the
  # Rails app and its existing Dhan integration.
  #
  # The adapter gem is PATH-INSTALLED on the operator workstation and is not
  # in this repo's Gemfile (it referenced /home/nemesis/... which does not
  # exist on CI or other machines). The class therefore guards on the
  # adapter's presence: without it, tools_for_ollama degrades to [] and call
  # returns a structured adapter_unavailable failure instead of raising
  # NameError at load/first-use.
  class DhanToolBridge
    ADAPTER_AVAILABLE = begin
      defined?(Dhanhq::Mcp) ? true : false
    rescue StandardError
      false
    end

    class << self
      def adapter_available?
        ADAPTER_AVAILABLE
      end

      def context
        @context ||= Dhanhq::Mcp::Context.new(client: dhanhq_client)
      end

      def dhanhq_client
        @dhanhq_client ||= DhanHQ::Client.new(api_type: :option_chain)
      end

      def tools_for_ollama
        return [] unless adapter_available?

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
        return unavailable_result(tool_name) unless adapter_available?

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

      private

      def unavailable_result(tool_name)
        Rails.logger.error(
          '[Ai::DhanToolBridge] dhanhq-mcp adapter is not installed ' \
          "(tool=#{tool_name}) — add the gem to the Gemfile to enable MCP tool bridging"
        )
        { error: 'adapter_unavailable', tool_name: tool_name,
          message: 'dhanhq-mcp adapter gem is not installed' }
      end
    end
  end
end
