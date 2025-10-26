# frozen_string_literal: true

require 'bigdecimal'

module Trading
  module Indicators
    module_function

    def rsi(closes, period: 14)
      return if closes.size < period + 1

      gains = []
      losses = []

      closes.each_cons(2) do |prev, curr|
        change = decimal(curr) - decimal(prev)
        if change.positive?
          gains << change
          losses << BigDecimal(0)
        else
          gains << BigDecimal(0)
          losses << change.abs
        end
      end

      avg_gain = average(gains.last(period))
      avg_loss = average(losses.last(period))
      return BigDecimal(50) if avg_loss.zero?

      rs = avg_gain / avg_loss
      100 - (100 / (1 + rs))
    end

    def atr(candles, period: 7)
      return if candles.size < period + 1

      trs = candles.each_cons(2).filter_map do |prev, curr|
        high = curr[:high]
        low = curr[:low]
        prev_close = prev[:close]

        next unless high && low && prev_close

        ranges = [high - low, (high - prev_close).abs, (low - prev_close).abs]
        ranges.compact.max
      end

      average(trs.last(period))
    end

    def supertrend(candles, period: 7, multiplier: 3)
      return if candles.size < period

      atr_value = atr(candles, period: period)
      return unless atr_value

      last_candle = candles.last
      hl2 = (decimal(last_candle[:high]) + decimal(last_candle[:low])) / 2
      basic_upper = hl2 + (multiplier * atr_value)
      basic_lower = hl2 - (multiplier * atr_value)

      close = decimal(last_candle[:close])
      return unless close

      trend = close > basic_upper ? :bearish : :bullish
      { trend: trend == :bearish ? :bearish : :bullish, band: trend == :bearish ? basic_upper : basic_lower }
    end

    def average(values)
      values = Array(values).compact.map { |value| decimal(value) }
      return BigDecimal(0) if values.empty?

      values.sum(BigDecimal(0)) / values.size
    end

    def decimal(value)
      return BigDecimal(0) if value.nil?

      BigDecimal(value.to_s)
    end
  end
end
