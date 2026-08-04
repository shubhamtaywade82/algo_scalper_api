# frozen_string_literal: true

module Backtest
  # Main backtest engine runner
  class Engine
    def initialize(data:, strategy:)
      @data = data
      @replayer = MarketReplayer.new(data: @data)
      @strategy_adapter = StrategyAdapter.new(strategy: strategy)
      @sim = TradeSimulator.new
      @portfolio = Portfolio.new(initial_capital: 100_000)
    end

    def run
      @replayer.each_tick do |tick|
        signal = @strategy_adapter.on_tick(tick)

        if signal == :buy
          @sim.enter(price: tick[:option_price], time: tick[:timestamp])
        elsif signal == :exit
          @sim.exit(price: tick[:option_price], time: tick[:timestamp])
        else
          @sim.update(price: tick[:option_price], time: tick[:timestamp])
        end
      end

      metrics = Metrics.new(trades: @sim.trades)
      Report.new(metrics: metrics, trades: @sim.trades).print
    end
  end

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
