module BacktestEngine
  module Strategies
    class Runner
      def initialize(index_candle:, indicators:, ltp:, strategy_class: ExpiryTrendV1)
        @index_candle = index_candle
        @indicators = indicators
        @ltp = ltp
        @strategy_class = strategy_class
      end

      def call
        context = Market::ContextBuilder.build(
          index_candle: index_candle,
          indicators: indicators,
          ltp: ltp
        )

        strategy = strategy_class.new(context: context)
        signal = strategy.call

        { signal: signal, context: context }
      end

      private

      attr_reader :index_candle, :indicators, :ltp, :strategy_class
    end
  end
end

