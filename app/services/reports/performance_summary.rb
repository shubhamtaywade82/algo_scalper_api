# frozen_string_literal: true

module Reports
  # Win/loss statistics and a per-day pnl series over a scope of exited trades.
  class PerformanceSummary
    def initialize(scope)
      @scope = scope
    end

    # @return [Hash] { summary: {...}, daily: [{ date:, pnl: }] }
    def call
      { summary: summary, daily: daily }
    end

    private

    def summary
      net_pnl = @scope.sum(:last_pnl_rupees).to_f

      {
        total_trades: total, wins: wins, losses: losses, win_rate_percent: win_rate,
        net_pnl: net_pnl,
        avg_win: average_pnl(winners, wins), avg_loss: average_pnl(losers, losses),
        max_win: @scope.maximum(:last_pnl_rupees).to_f, max_loss: @scope.minimum(:last_pnl_rupees).to_f,
        profit_factor: profit_factor,
        expectancy: total.positive? ? (net_pnl / total).round(2) : 0.0
      }
    end

    def total
      @total ||= @scope.count
    end

    def wins
      @wins ||= winners.count
    end

    def losses
      @losses ||= losers.count
    end

    def winners
      @scope.where('last_pnl_rupees > 0')
    end

    # Flat trades count as losses, matching how the dashboard has always reported them.
    def losers
      @scope.where('last_pnl_rupees <= 0')
    end

    def win_rate
      total.positive? ? (wins.to_f / total * 100).round(2) : 0.0
    end

    def average_pnl(trades, count)
      count.positive? ? (trades.sum(:last_pnl_rupees).to_f / count).round(2) : 0.0
    end

    # Gross profit / gross loss. The payoff ratio (avg win / avg loss) overstated this
    # (2.33 vs a true ~1.01 on the paper history).
    def profit_factor
      gross_loss = @scope.where('last_pnl_rupees < 0').sum(:last_pnl_rupees).to_f.abs
      gross_profit = winners.sum(:last_pnl_rupees).to_f
      gross_loss.positive? ? (gross_profit / gross_loss).round(2) : 0.0
    end

    def daily
      @scope.group(Arel.sql('DATE(exited_at)'))
            .pluck(Arel.sql('DATE(exited_at)'), Arel.sql('SUM(last_pnl_rupees)'))
            .map { |date, pnl| { date: date.to_s, pnl: pnl.to_f.round(2) } }
            .sort_by { |entry| entry[:date] }
    end
  end
end
