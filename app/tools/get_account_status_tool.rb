# frozen_string_literal: true

class GetAccountStatusTool < RubyLLM::Tool
  description "Fetches the current account funds, available margin, paper/live trading stats (win rate, realized and unrealized PnL), and active open positions."

  def execute(_ = nil)
    is_live         = !AlgoConfig.paper_trading_enabled?
    available_cash  = Capital::Allocator.available_cash.to_f
    stats           = PositionTracker.paper_trading_stats_with_pct(date: Time.zone.today)
    active_positions = is_live ? PositionTracker.live.active : PositionTracker.paper.active

    {
      mode: is_live ? "LIVE" : "PAPER_TRADING",
      available_capital: available_cash,
      trading_stats_today: {
        total_trades: stats[:total_trades],
        winners: stats[:winners],
        losers: stats[:losers],
        win_rate: stats[:win_rate],
        realized_pnl: stats[:realized_pnl_rupees],
        realized_pnl_pct: stats[:realized_pnl_pct],
        unrealized_pnl: active_positions.sum(&:last_pnl_rupees).to_f
      },
      active_positions: active_positions.map do |p|
        {
          symbol: p.symbol,
          entry_price: p.entry_price.to_f,
          quantity: p.quantity.to_i,
          current_pnl: p.last_pnl_rupees.to_f,
          current_pnl_pct: (p.last_pnl_pct || 0).to_f * 100
        }
      end,
      timestamp: Time.current
    }
  rescue StandardError => e
    { error: "Failed to fetch account status: #{e.message}" }
  end
end
