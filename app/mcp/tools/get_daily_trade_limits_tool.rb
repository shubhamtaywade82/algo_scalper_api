# frozen_string_literal: true

class GetDailyTradeLimitsTool < ApplicationMCPTool
  tool_name 'get_daily_trade_limits'
  description 'Per-index daily loss, trade count and remaining loss budget from the shared daily-limits store, ' \
              'plus the global daily loss. Read-only.'

  def perform
    snapshot = market_snapshot
    limits = Live::DailyLimits.new

    per_index = Array(snapshot['indices']).map do |i|
      key = i['index_key']
      {
        index_key: key,
        daily_loss_rupees: limits.get_daily_loss(key).to_f.round(2),
        trades_today: limits.get_daily_trades(key).to_i,
        remaining_loss_budget_rupees: limits.remaining_loss_budget(index_key: key).to_f.round(2)
      }
    end

    render_json(
      generated_at: snapshot['generated_at'],
      global_daily_loss_rupees: limits.get_global_daily_loss.to_f.round(2),
      indices: per_index
    )
  end
end
