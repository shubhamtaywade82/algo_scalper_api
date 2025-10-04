# frozen_string_literal: true

module Indicators
  class Calculator
    def initialize(series)
      @series = series
    end

    def rsi(period = 14)
      RubyTechnicalAnalysis::RelativeStrengthIndex.new(series: @series.closes, period:).call
    end

    def macd
      RubyTechnicalAnalysis::Macd.new(series: @series.closes).call
    end

    def adx(period = 14)
      hlc = @series.candles.each_with_index.map do |c, _i|
        {
          date_time: Time.zone.at(c.timestamp || 0),
          high: c.high,
          low: c.low,
          close: c.close
        }
      end
      TechnicalAnalysis::Adx.calculate(hlc, period:).last.adx
    end

    def bullish_signal?
      rsi < 30 && adx > 20 && @series.closes.last > @series.closes[-2]
    end

    def bearish_signal?
      rsi > 70 && adx > 20 && @series.closes.last < @series.closes[-2]
    end
  end
end


