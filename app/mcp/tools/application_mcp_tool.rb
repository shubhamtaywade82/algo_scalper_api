# frozen_string_literal: true

# MCP tools are read-only views over the trading system. They must never reach
# Orders::*, gateways or the DhanHQ order API (enforced by spec/mcp/application_mcp_tool_spec.rb).
class ApplicationMCPTool < ActionMCP::Tool
  abstract!

  # Keys matching this never leave the process unredacted (see redact).
  SECRET_KEY_PATTERN = /token|secret|password|passwd|api_key|apikey|webhook|credential/i

  private

  # Market Brief snapshot: cross-process sources (Redis/DB) with explicit status,
  # observed_at and age_seconds, so a client can't mistake stale data for live.
  def market_snapshot
    @market_snapshot ||= Reports::MarketBrief::SnapshotBuilder.call
  end

  # Recursively masks secret-looking keys before any config data leaves the process.
  def redact(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, val), out|
        out[key.to_s] = SECRET_KEY_PATTERN.match?(key.to_s) ? 'REDACTED' : redact(val)
      end
    when Array then value.map { |v| redact(v) }
    else value
    end
  end

  # Text JSON for small local models that ignore structuredContent.
  def render_json(payload)
    render text: payload.to_json
  end
end
