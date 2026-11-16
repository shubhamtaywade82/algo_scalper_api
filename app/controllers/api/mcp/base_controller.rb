# frozen_string_literal: true

module Api
  module MCP
    # Dashboard window onto the local ActionMCP server (bin/mcp). Goes through MCP over
    # loopback like any other client, so the page shows exactly what Cursor/Claude see.
    class BaseController < ApplicationController
      include Api::TokenAuthenticatable

      UNREACHABLE_ERRORS = [Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Net::OpenTimeout, Net::ReadTimeout].freeze

      before_action :authenticate_dashboard_token!

      private

      # Loopback call: the MCP gateway lets same-machine clients in without a token.
      def bridge
        @bridge ||= ::MCP::OllamaBridge.new
      end

      def render_mcp_error(error)
        render json: { error: error.message }, status: :bad_gateway
      end
    end
  end
end
