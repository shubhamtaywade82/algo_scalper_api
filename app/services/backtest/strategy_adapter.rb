# frozen_string_literal: true

module Backtest
  # Connects the strategy to the backtest harness
  class StrategyAdapter
    def initialize(strategy:)
      @strategy = strategy
    end

    def on_tick(tick)
      @strategy.process(tick)
    end
  end

  # Tracks capital and portfolio metrics
  class Portfolio
    attr_reader :capital

    def initialize(initial_capital:)
      @capital = initial_capital.to_f
    end

    def apply_trade(trade)
      @capital += trade[:pnl]
    end
  end
end
