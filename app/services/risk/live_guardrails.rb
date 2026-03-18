module Risk
  class LiveGuardrails
    MAX_DAILY_DRAWDOWN = 0.05
    MAX_CONSECUTIVE_LOSSES = 5

    def initialize(equity:, trades:)
      @equity = equity
      @trades = trades
    end

    def allow_trading?
      return false if drawdown_exceeded?
      return false if consecutive_losses_exceeded?

      true
    end

    private

    def drawdown_exceeded?
      peak = @equity.max
      current = @equity.last
      return false if peak.nil? || current.nil?

      ((peak - current) / peak.to_f) > MAX_DAILY_DRAWDOWN
    end

    def consecutive_losses_exceeded?
      losses = @trades.last(MAX_CONSECUTIVE_LOSSES)
      return false if losses.size < MAX_CONSECUTIVE_LOSSES

      losses.all? { |t| t[:pnl] <= 0 }
    end
  end
end
