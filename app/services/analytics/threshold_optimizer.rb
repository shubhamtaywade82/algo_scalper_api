# frozen_string_literal: true

module Analytics
  class ThresholdOptimizer
    SCORE_RANGE = (40..90).step(5)

    def initialize(trades)
      @trades = trades
    end

    def call
      results = SCORE_RANGE.map do |threshold|
        filtered = @trades.select { |t| t[:context].score >= threshold }
        metrics = compute(filtered)

        {
          threshold: threshold,
          trades: filtered.size,
          win_rate: metrics[:win_rate],
          expectancy: metrics[:expectancy]
        }
      end

      best = results.max_by { |r| r[:expectancy] || -Float::INFINITY }

      {
        best_threshold: best,
        all_results: results
      }
    end

    private

    def compute(trades)
      return { win_rate: 0, expectancy: 0 } if trades.empty?

      wins = trades.select { |t| t[:pnl].positive? }
      losses = trades.select { |t| t[:pnl] <= 0 }

      total = trades.size
      win_rate = wins.size.to_f / total

      avg_win = wins.sum { |t| t[:pnl] } / (wins.size.nonzero? || 1).to_f
      avg_loss = losses.sum { |t| t[:pnl] }.abs / (losses.size.nonzero? || 1).to_f

      expectancy = (win_rate * avg_win) - ((1 - win_rate) * avg_loss)

      {
        win_rate: win_rate,
        expectancy: expectancy
      }
    end
  end
end
