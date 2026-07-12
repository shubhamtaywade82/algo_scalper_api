module BacktestEngine
  class StrategyEngine
    def initialize
      @position = nil
    end

    def on_tick(index_candle, context)
      signal = generate_signal(index_candle, context)
      handle_signal(signal, context)
    end

    private

    def generate_signal(index_candle, context) # rubocop:disable Lint/UnusedMethodArgument
      structure = context[:structure]

      return :buy_call if structure == :bullish
      return :buy_put if structure == :bearish

      nil
    end

    def handle_signal(signal, context)
      case signal
      when :buy_call
        enter(:call, context)
      when :buy_put
        enter(:put, context)
      when :exit
        exit_position(context)
      end
    end

    def enter(type, context)
      return if @position

      @position = {
        type: type,
        entry_price: context[:option_price],
        entry_time: context[:timestamp]
      }
    end

    def exit_position(context)
      return unless @position

      pnl = context[:option_price] - @position[:entry_price]
      @position = nil
      pnl
    end
  end
end

