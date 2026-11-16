# frozen_string_literal: true

class GetSystemHealthTool < ApplicationMCPTool
  tool_name 'get_system_health'
  description 'Health of the market feed, signal scheduler, trading daemon, order-update feed and reconciliation, ' \
              'plus data freshness warnings. Read-only.'

  def perform
    snapshot = market_snapshot
    render_json(
      generated_at: snapshot['generated_at'],
      health: snapshot['health'],
      freshness: snapshot['freshness'],
      warnings: snapshot['warnings']
    )
  end
end
