module Analytics
  class Metrics
    def initialize(trades, equity_curve)
      @trades = trades
      @equity_curve = equity_curve
    end

    def call
      {
        total_trades: total_trades,
        win_rate: win_rate,
        avg_win: avg_win,
        avg_loss: avg_loss,
        expectancy: expectancy,
        max_drawdown: max_drawdown
      }
    end

    private

    def total_trades
      @trades.size
    end

    def win_rate
      return 0 if total_trades == 0
      wins.size.to_f / total_trades
    end

    def wins
      @trades.select { |t| t[:pnl] > 0 }
    end

    def losses
      @trades.select { |t| t[:pnl] <= 0 }
    end

    def avg_win
      return 0 if wins.empty?
      wins.sum { |t| t[:pnl] } / wins.size.to_f
    end

    def avg_loss
      return 0 if losses.empty?
      losses.sum { |t| t[:pnl] }.abs / losses.size.to_f
    end

    def expectancy
      (win_rate * avg_win) - ((1 - win_rate) * avg_loss)
    end

    def max_drawdown
      peak = -Float::INFINITY
      max_dd = 0

      @equity_curve.each do |value|
        peak = [peak, value].max
        dd = peak - value
        max_dd = [max_dd, dd].max
      end

      max_dd
    end
  end
end
