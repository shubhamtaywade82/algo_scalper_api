# frozen_string_literal: true

module Paper
  class PerformanceReport
    class << self
      def generate!
        trades = PaperTrade.all
        total_net = trades.sum(:net_pnl)
        wins = trades.where('net_pnl > 0').count
        losses = trades.where('net_pnl < 0').count
        total = trades.count
        win_rate = total.positive? ? (wins.to_f / total) : 0.0
        avg_gain = trades.where('net_pnl > 0').average(:net_pnl)&.to_f || 0.0
        avg_loss = trades.where('net_pnl < 0').average(:net_pnl)&.to_f || 0.0
        best = trades.maximum(:net_pnl)&.to_f || 0.0
        worst = trades.minimum(:net_pnl)&.to_f || 0.0

        {
          total_trades: total,
          net_pnl: total_net.to_f,
          win_rate: win_rate.round(4),
          avg_gain: avg_gain,
          avg_loss: avg_loss,
          best_trade: best,
          worst_trade: worst
        }
      end
    end
  end
end
