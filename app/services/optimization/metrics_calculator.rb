# frozen_string_literal: true

module Optimization
  class MetricsCalculator
    def initialize(trades:)
      @trades = trades
    end

    def compute
      return empty_metrics if @trades.empty?

      returns = @trades.map { |t| t[:exit] - t[:entry] }

      wins = returns.select { |r| r > 0 }
      losses = returns.select { |r| r <= 0 }

      win_rate = wins.count.to_f / @trades.count
      avg_win = wins.sum / wins.count rescue 0
      avg_loss = losses.sum.abs / losses.count rescue 0

      expectancy = (win_rate * avg_win) - ((1 - win_rate) * avg_loss)

      # Sharpe: mean return / std dev
      mean_return = returns.sum / returns.size.to_f
      variance = returns.map { |r| (r - mean_return)**2 }.sum / returns.size.to_f
      std_dev = Math.sqrt(variance)
      sharpe = std_dev.positive? ? (mean_return / std_dev) : 0.0

      {
        win_rate: win_rate.round(4),
        expectancy: expectancy.round(4),
        sharpe: sharpe.round(4),
        net_pnl: returns.sum.round(2),
        avg_move: mean_return.round(4)
      }
    rescue StandardError => e
      Rails.logger.error("[MetricsCalculator] Calculation failed: #{e.class} - #{e.message}")
      empty_metrics
    end

    private

    def empty_metrics
      {
        win_rate: 0.0,
        expectancy: 0.0,
        sharpe: 0.0,
        net_pnl: 0.0,
        avg_move: 0.0
      }
    end
  end
end

