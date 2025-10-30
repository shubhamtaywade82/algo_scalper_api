# frozen_string_literal: true

require 'bigdecimal'

module Trading
  class TrendIdentifier
    def initialize(data_fetcher: DataFetcherService.new)
      @data_fetcher = data_fetcher
    end

    def signal_for(instrument)
      candles = @data_fetcher.fetch_historical_data(
        instrument: instrument,
        interval: '5minute',
        lookback: 120
      )
      return if candles.blank?

      closes = candles.filter_map { |candle| candle[:close] }.map { |value| BigDecimal(value.to_s) }
      return if closes.size < 30

      rsi_value = Indicators.rsi(closes)
      supertrend = Indicators.supertrend(candles.last(20))
      sma_fast = simple_moving_average(closes.last(9))
      sma_slow = simple_moving_average(closes.last(21))

      bullish = supertrend && supertrend[:trend] == :bullish
      momentum = sma_fast && sma_slow && sma_fast > sma_slow
      rsi_confirmed = rsi_value&.between?(BigDecimal(40), BigDecimal(70))

      return :long if bullish && momentum && rsi_confirmed

      nil
    end

    private

    def simple_moving_average(values)
      values = Array(values).compact
      return if values.empty?

      values.sum / values.size
    end
  end
end
