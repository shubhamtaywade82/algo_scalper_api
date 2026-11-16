# frozen_string_literal: true

class GetTradingModeTool < ApplicationMCPTool
  tool_name 'get_trading_mode'
  description 'Effective trading mode: paper/live gateway mode, run_mode profile, and whether live order submission ' \
              'is enabled. Read-only; cannot change the mode.'

  def perform
    cfg = AlgoConfig.fetch

    render_json(
      mode: AlgoConfig.mode.to_s,
      run_mode: AlgoConfig.run_mode,
      paper_trading_enabled: AlgoConfig.paper_trading_enabled?,
      live_order_submission_enabled: cfg.dig(:dhanhq, :enable_orders) == true
    )
  end
end
