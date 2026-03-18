module Analytics
  class StrategyEvaluator
    MIN_TRADES = 30

    def initialize(trades, metrics)
      @trades = trades
      @metrics = metrics
    end

    def call
      return insufficient_data if @trades.size < MIN_TRADES

      {
        status: status,
        verdict: verdict,
        suggestions: suggestions
      }
    end

    private

    def status
      {
        trades: @trades.size,
        win_rate: @metrics[:win_rate],
        expectancy: @metrics[:expectancy],
        drawdown: @metrics[:max_drawdown]
      }
    end

    def verdict
      return :reject if @metrics[:expectancy] <= 0
      return :high_risk if @metrics[:max_drawdown] > 0.25 * peak_capital
      return :weak if @metrics[:win_rate] < 0.3

      :valid
    end

    def suggestions
      suggestions = []

      suggestions << "Increase regime score threshold" if @metrics[:win_rate] < 0.35
      suggestions << "Reduce drawdown via tighter SL" if @metrics[:max_drawdown] > 0.2 * peak_capital
      suggestions << "Focus on high score trades only" if @metrics[:expectancy] < 0.2

      suggestions
    end

    def insufficient_data
      {
        status: :insufficient_data,
        message: "Need at least #{MIN_TRADES} trades"
      }
    end

    def peak_capital
      100_000.0
    end
  end
end
