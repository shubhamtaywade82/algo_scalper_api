module BacktestEngine
  class Runner
    def initialize(index_candles:, option_data:, lot_size:, strategy: StrategyEngine.new)
      @index_engine = IndexEngine.new(index_candles)
      @option_mapper = OptionMapper.new(option_data)
      @execution_engine = ExecutionEngine.new(lot_size: lot_size)
      @strategy = strategy
      @metrics = Metrics.new
    end

    attr_reader :metrics

    def run
      index_engine.each_candle do |index_candle, index|
        structure = index_engine.structure_state(index)
        strike_info = option_mapper.select_strike(index_candle.close, structure)
        next unless strike_info

        option_candle = option_mapper.price_at(
          index_candle.timestamp,
          strike_info[:strike],
          strike_info[:type]
        )

        next unless option_candle

        context = build_context(index_candle, structure, option_candle)
        handle_tick(index_candle, context)
      end

      metrics
    end

    private

    attr_reader :index_engine, :option_mapper, :execution_engine, :strategy

    def build_context(index_candle, structure, option_candle)
      {
        structure: structure,
        option_price: option_candle[:close],
        timestamp: index_candle.timestamp
      }
    end

    def handle_tick(index_candle, context)
      result = strategy.on_tick(index_candle, context)
      return unless result.is_a?(Numeric)

      metrics.record_trade(result)
    end
  end
end

