# frozen_string_literal: true

class GetRiskStatusTool < ApplicationMCPTool
  tool_name 'get_risk_status'
  description "Today's P&L, open positions, exposure, daily-loss utilisation and circuit breaker state. Read-only."

  def perform
    snapshot = market_snapshot
    render_json(generated_at: snapshot['generated_at'], mode: snapshot['mode'], risk: snapshot['risk'])
  end
end
