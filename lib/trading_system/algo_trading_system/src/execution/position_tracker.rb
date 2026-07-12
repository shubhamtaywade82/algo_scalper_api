# frozen_string_literal: true

module Execution
  # Tracks open positions and daily P&L
  class PositionTracker
    attr_reader :open_positions, :closed_positions, :daily_pnl

    Position = Struct.new(:symbol, :quantity, :entry_price, :current_price, keyword_init: true) do
      def pnl
        (current_price - entry_price) * quantity
      end
    end

    def initialize
      @open_positions = {}
      @closed_positions = []
      @daily_pnl = 0.0
    end

    def on_order_filled(order)
      if order.transaction_type == 'BUY'
        if @open_positions[order.symbol]
          pos = @open_positions[order.symbol]
          total_qty = pos.quantity + order.quantity
          avg_price = ((pos.entry_price * pos.quantity) + (order.filled_price * order.quantity)) / total_qty.to_f
          pos.quantity = total_qty
          pos.entry_price = avg_price
          pos.current_price = order.filled_price
        else
          @open_positions[order.symbol] = Position.new(
            symbol: order.symbol,
            quantity: order.quantity,
            entry_price: order.filled_price,
            current_price: order.filled_price
          )
        end
      elsif order.transaction_type == 'SELL'
        pos = @open_positions[order.symbol]
        return unless pos

        sell_qty = [pos.quantity, order.quantity].min
        realized_pnl = (order.filled_price - pos.entry_price) * sell_qty
        @daily_pnl += realized_pnl

        pos.quantity -= sell_qty
        if pos.quantity <= 0
          @closed_positions << @open_positions.delete(order.symbol)
        end
      end
    end

    def on_tick(tick)
      pos = @open_positions[tick.symbol]
      pos.current_price = tick.last_price if pos
    end

    def on_candle(candle)
      pos = @open_positions[candle.symbol]
      pos.current_price = candle.close if pos
    end

    def total_unrealized_pnl
      @open_positions.values.sum(&:pnl)
    end
  end
end
