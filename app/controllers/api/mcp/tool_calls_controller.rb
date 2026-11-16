# frozen_string_literal: true

module Api
  module MCP
    class ToolCallsController < BaseController
      # POST /api/mcp/tools/:tool_id/calls  { arguments: {} }
      def create
        # Arguments are dynamic JSON forwarded to MCP bridge, not passed to Active Record persistence.
        arguments = params[:arguments].is_a?(ActionController::Parameters) ? params[:arguments].to_unsafe_h : params.fetch(:arguments, {}).to_h
        text = bridge.call_tool(params[:tool_id], arguments)
        render json: { name: params[:tool_id], result: parse_json(text) }, status: :created
      rescue *UNREACHABLE_ERRORS, ::MCP::OllamaBridge::Error => e
        render_mcp_error(e)
      end

      private

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError
        text
      end
    end
  end
end
