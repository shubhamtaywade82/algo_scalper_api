# frozen_string_literal: true

module OptionsBuying
  # PerformanceDb queries the historical database records of exited positions
  # to compute actual win rate and payout ratio (R:R) for dynamic Kelly sizing.
  class PerformanceDb
    MIN_TRADES_REQUIRED = 10

    def self.stats_for(strategy_name, index_key = nil)
      query = PositionTracker.where(status: :exited)
      query = query.where(entry_strategy: strategy_name) if strategy_name.present?
      query = query.where(index_key: index_key.to_s.upcase) if index_key.present?

      # Query recent 50 trades to adapt to recent performance regime
      trades = query.order(exited_at: :desc).limit(50).to_a
      return nil if trades.size < MIN_TRADES_REQUIRED

      wins = trades.select { |t| t.last_pnl_rupees.to_f > 0 }
      losses = trades.select { |t| t.last_pnl_rupees.to_f <= 0 }

      win_rate = wins.size.to_f / trades.size.to_f

      avg_win = wins.any? ? (wins.sum { |t| t.last_pnl_rupees.to_f } / wins.size) : 0.0
      avg_loss = losses.any? ? (losses.sum { |t| t.last_pnl_rupees.to_f }.abs / losses.size) : 1.0

      payout_ratio = avg_loss.positive? ? (avg_win / avg_loss) : 1.0

      {
        win_rate: win_rate.round(4),
        payout_ratio: payout_ratio.round(4),
        sample_size: trades.size,
        avg_win: avg_win.round(2),
        avg_loss: avg_loss.round(2)
      }
    rescue StandardError => e
      Rails.logger.error("[PerformanceDb] Stats query failed: #{e.message}")
      nil
    end
  end
end
