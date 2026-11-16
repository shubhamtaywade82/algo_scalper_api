# frozen_string_literal: true

class GetOpenPositionsTool < ApplicationMCPTool
  tool_name 'get_open_positions'
  description 'Open positions with entry price, LTP, P&L, stop and target, plus total exposure. Read-only.'

  def perform
    snapshot = market_snapshot
    risk = snapshot['risk']

    render_json(
      generated_at: snapshot['generated_at'],
      active_positions_count: risk['active_positions_count'],
      active_positions: risk['active_positions'],
      exposure_rupees: risk['exposure_rupees'],
      exposure_pct_of_capital: risk['exposure_pct_of_capital'],
      capital_available: risk['capital_available']
    )
  end
end
