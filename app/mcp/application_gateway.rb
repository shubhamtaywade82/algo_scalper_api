# frozen_string_literal: true

# Clients on this machine (Cursor, Claude Code, mcp:ask) need no token. Remote clients
# need `Authorization: Bearer $MCP_API_TOKEN`; unset token = open in dev, closed in production.
# The dashboard never talks to the MCP server; only AI clients do.
class ApplicationGateway < ActionMCP::Gateway
  class TokenIdentifier < ActionMCP::GatewayIdentifier
    identifier :user
    authenticates :mcp_token

    def resolve
      return 'local_client' if local_request?

      expected = ENV.fetch('MCP_API_TOKEN', '').presence
      return 'mcp_client' if expected.nil? && !Rails.env.production?
      raise Unauthorized, 'MCP_API_TOKEN not configured' unless expected

      provided = extract_bearer_token.to_s
      raise Unauthorized, 'Invalid MCP token' unless ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      'mcp_client'
    end

    private

    # Raw socket peer, not request.remote_ip: a same-host reverse proxy would make every
    # remote client look local, so any forwarding header disqualifies the request.
    def local_request?
      return false if @request.headers['X-Forwarded-For'].present? || @request.headers['Forwarded'].present?

      IPAddr.new(@request.remote_addr.to_s).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  identified_by TokenIdentifier
end
