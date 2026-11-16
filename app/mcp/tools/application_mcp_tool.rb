# frozen_string_literal: true

# MCP tools are read-only views over the trading system. They must never reach
# Orders::*, gateways or the DhanHQ order API (enforced by spec/mcp/application_mcp_tool_spec.rb).
class ApplicationMCPTool < ActionMCP::Tool
  abstract!

  private

  # Market Brief snapshot: cross-process sources (Redis/DB) with explicit status,
  # observed_at and age_seconds, so a client can't mistake stale data for live.
  def market_snapshot
    @market_snapshot ||= Reports::MarketBrief::SnapshotBuilder.call
  end

  # Text JSON for small local models that ignore structuredContent.
  def render_json(payload)
    render text: payload.to_json
  end
end
