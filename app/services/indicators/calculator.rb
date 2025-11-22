# frozen_string_literal: true

module Indicators
  class Calculator
    def initialize(series)
      @series = series
    end

    def rsi(period = 14)
      # Use CandleSeries helper method instead of duplicating logic
      @series.rsi(period)
    end

    def macd(fast_period = 12, slow_period = 26, signal_period = 9)
      # Use CandleSeries helper method instead of duplicating logic
      @series.macd(fast_period, slow_period, signal_period)
    end

    def adx(period = 14)
      # Use CandleSeries helper method instead of duplicating hlc logic
      @series.adx(period)
    end

    def bullish_signal?
      rsi < 30 && adx > 20 && @series.closes.last > @series.closes[-2]
    end

    def bearish_signal?
      rsi > 70 && adx > 20 && @series.closes.last < @series.closes[-2]
    end
  end
end
