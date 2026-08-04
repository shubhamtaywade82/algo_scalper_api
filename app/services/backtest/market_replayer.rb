# frozen_string_literal: true

module Backtest
  # Feeds historical ticks sequentially
  class MarketReplayer
    def initialize(data:)
      @data = data
    end

    def each_tick(&)
      @data.each(&)
    end
  end

  # Simulates fills and trade lifecycle
  class TradeSimulator
    attr_reader :trades, :active_position

    def initialize
      @active_position = nil
      @trades = []
    end

    def enter(price:, time:)
      return if @active_position
      @active_position = {
        entry_price: price,
        entry_time: time,
        highest: price
      }
    end

    def update(price:, time:)
      return unless @active_position
      @active_position[:highest] = [@active_position[:highest], price].max
    end

    def exit(price:, time:)
      return unless @active_position
      @trades << {
        entry: @active_position[:entry_price],
        exit: price,
        pnl: price - @active_position[:entry_price],
        entry_time: @active_position[:entry_time],
        exit_time: time
      }
      @active_position = nil
    end
  end
end
