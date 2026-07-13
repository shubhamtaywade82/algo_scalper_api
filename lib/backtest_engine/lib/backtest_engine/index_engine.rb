module BacktestEngine
  class IndexEngine
    def initialize(candles)
      @candles = Array(candles)
    end

    def each_candle
      return enum_for(:each_candle) unless block_given?

      @candles.each_with_index do |candle, index|
        yield(candle, index)
      end
    end

    def structure_state(index)
      return :neutral if index < 1 || index >= @candles.size

      previous = @candles[index - 1]
      current = @candles[index]

      return :range unless previous && current

      bullish?(previous, current) ? :bullish : bearish_or_range(previous, current)
    end

    private

    def bullish?(previous, current)
      current.high > previous.high && current.low > previous.low
    end

    def bearish_or_range(previous, current)
      return :bearish if current.low < previous.low && current.high < previous.high

      :range
    end
  end
end

