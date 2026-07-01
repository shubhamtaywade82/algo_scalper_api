# frozen_string_literal: true

module Ai
  # Bridges MCP tool calls into the Ollama function-calling flow.
  #
  # This uses the local `dhanhq-mcp` adapter for validated DhanHQ tool specs
  # and routing, while keeping auth, risk, and execution controlled by the
  # Rails app and its existing Dhan integration.
  class DhanToolBridge
    MCP_TOOL_NAMES = Dhanhq::Mcp::TOOL_SPEC.filter_map { |t| t[:name] }.freeze

    class << self
      def context
        @context ||= Dhanhq::Mcp::Context.new(client: dhanhq_client)
      end

      def dhanhq_client
        @dhanhq_client ||= DhanHQ::Client.new(api_type: :option_chain)
      end

      # Schema overrides for tools that need better descriptions or enums
      TOOL_OVERRIDES = {
        'instrument.find' => {
          description: 'Find instrument by symbol. Use exchange_segment IDX_I for indices (NIFTY, BANKNIFTY, SENSEX), NSE_EQ for stocks, NSE_FNO for F&O.',
          parameters: {
            type: 'object',
            properties: {
              exchange_segment: { type: 'string', enum: %w[NSE_EQ NSE_FNO NSE_CURRENCY NSE_COMM BSE_EQ BSE_FNO BSE_CURRENCY MCX_COMM IDX_I] },
              symbol: { type: 'string', description: 'Trading symbol, e.g. NIFTY, BANKNIFTY, SENSEX, RELIANCE' }
            },
            required: %w[exchange_segment symbol]
          }
        },
        'option.chain' => {
          description: 'Fetch option chain for an expiry. Returns last_price and strikes with call/put data.',
          parameters: {
            type: 'object',
            properties: {
              exchange_segment: { type: 'string' },
              symbol: { type: 'string' },
              expiry: { type: 'string', description: 'Expiry date YYYY-MM-DD' }
            },
            required: %w[exchange_segment symbol expiry]
          }
        }
      }.freeze

      def tools_for_ollama
        Dhanhq::Mcp::TOOL_SPEC.filter_map do |tool|
          override = TOOL_OVERRIDES[tool[:name]]
          {
            type: "function",
            function: {
              name: tool[:name],
              description: override&.dig(:description) || tool[:description],
              parameters: override&.dig(:parameters) || tool[:input_schema]
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
