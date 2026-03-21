# frozen_string_literal: true

module Backtest
  # Calculates performance statistics from trades
  class Metrics
    def initialize(trades:)
      @trades = Array(trades)
    end

    def win_rate
      return 0.0 if @trades.empty?
      wins = @trades.count { |t| t[:pnl].positive? }
      wins.to_f / @trades.size
    end

    def profit_factor
      return 0.0 if @trades.empty?
      gains = @trades.select { |t| t[:pnl].positive? }.sum { |t| t[:pnl] }
      losses = @trades.select { |t| t[:pnl].negative? }.sum { |t| t[:pnl].abs }

      return gains.to_f if losses.zero?
      gains / losses
    end

    def max_drawdown
      return 0.0 if @trades.empty?
      equity = 0.0
      peak = 0.0
      dd = 0.0

      @trades.each do |t|
        equity += t[:pnl]
        peak = [peak, equity].max
        dd = [dd, peak - equity].max
      end

      dd
    end
  end
end
