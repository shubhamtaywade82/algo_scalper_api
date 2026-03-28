# frozen_string_literal: true

module Analytics
  class TradeBreakdown
    def initialize(trades)
      @trades = trades
    end

    def call
      {
        by_regime: breakdown(:regime),
        by_session: breakdown(:session),
        by_day_type: breakdown(:day_type),
        by_score_bucket: breakdown_score
      }
    end

    private

    def breakdown(key)
      grouped = @trades.group_by { |t| t[:context].send(key) }

      grouped.transform_values do |group|
        compute(group)
      end
    end

    def breakdown_score
      buckets = {
        high: @trades.select { |t| t[:context].score >= 70 },
        medium: @trades.select { |t| t[:context].score.between?(50, 69) },
        low: @trades.select { |t| t[:context].score < 50 }
      }

      buckets.transform_values { |group| compute(group) }
    end

    def compute(trades)
      wins = trades.select { |t| t[:pnl] > 0 }
      losses = trades.select { |t| t[:pnl] <= 0 }

      total = trades.size
      return {} if total == 0

      avg_win = wins.sum { |t| t[:pnl] } / (wins.size.nonzero? || 1).to_f
      avg_loss = losses.sum { |t| t[:pnl] }.abs / (losses.size.nonzero? || 1).to_f

      {
        total: total,
        win_rate: wins.size.to_f / total,
        expectancy: (wins.size.to_f / total * avg_win) - ((1 - wins.size.to_f / total) * avg_loss)
      }
    end
  end
end
