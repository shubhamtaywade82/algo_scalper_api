# frozen_string_literal: true

module Backtest
  # Prints the backtest report
  class Report
    def initialize(metrics:, trades:)
      @metrics = metrics
      @trades = trades
    end

    def print
      Rails.logger.debug "\n--- Backtest Report ---"
      Rails.logger.debug "Trades: #{@trades.size}"
      Rails.logger.debug "Win Rate: #{(@metrics.win_rate * 100).round(2)}%"
      Rails.logger.debug "Profit Factor: #{@metrics.profit_factor.round(2)}"
      Rails.logger.debug "Max Drawdown: ₹#{@metrics.max_drawdown.round(2)}"
      Rails.logger.debug "-----------------------\n"
    end
  end
end
