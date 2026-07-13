module BacktestEngine
  module Portfolio
    class Portfolio
      attr_reader :starting_capital, :cash, :equity_curve, :positions

      def initialize(starting_capital:)
        @starting_capital = starting_capital.to_f
        @cash = @starting_capital
        @equity_curve = []
        @positions = []
      end

      def can_open?(required_margin)
        cash >= required_margin
      end

      def open_position!(signal, entry_price, lot_size, quantity)
        cost = entry_price * lot_size * quantity
        return nil unless can_open?(cost)

        @cash -= cost
        position = {
          signal: signal,
          entry_price: entry_price,
          lot_size: lot_size,
          quantity: quantity
        }
        positions << position
        position
      end

      def close_position!(position, exit_price, execution_engine)
        pnl = execution_engine.pnl(position[:entry_price], exit_price)
        @cash += (position[:entry_price] * position[:lot_size] * position[:quantity]) + pnl
        positions.delete(position)
        pnl
      end

      def record_equity(pnl: 0.0)
        equity_curve << cash + open_position_value + pnl
      end

      def max_drawdown
        peak = starting_capital
        max_dd = 0.0

        equity_curve.each do |value|
          peak = [peak, value].max
          dd = (peak - value) / peak
          max_dd = [max_dd, dd].max
        end

        max_dd
      end

      private

      def open_position_value
        0.0
      end
    end
  end
end

