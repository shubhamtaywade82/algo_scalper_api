# frozen_string_literal: true

class GetLivePnlTool < ApplicationMCPTool
  tool_name 'get_live_pnl'
  description "Today's realized and unrealized P&L for the active trading mode, plus the realized daily-loss budget. Read-only."

  def perform
    snapshot = market_snapshot
    risk = snapshot['risk']

    render_json(
      generated_at: snapshot['generated_at'],
      pnl: risk['pnl'],
      daily_loss: risk['daily_loss'],
      capital_available: risk['capital_available']
    )
  end
end
