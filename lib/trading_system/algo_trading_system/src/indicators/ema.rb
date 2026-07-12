# frozen_string_literal: true

require_relative 'indicator_base'

module Indicators
  # Exponential Moving Average
  class Ema < IndicatorBase
    attr_reader :period, :value, :history

    def initialize(period:)
      super()
      @period = period
      @history = []
      @value = nil
    end

    def update(candle)
      price = candle.close
      @history << price

      return if too_few_prices?

      if @history.size == @period
        @value = @history.sum / @period.to_f
        return
      end

      calculate_ema(price)
      @history.shift if @history.size > @period + 1
    end

    def ready?
      @history.size >= @period
    end

    private

    def too_few_prices?
      @history.size < @period
    end

    def calculate_ema(price)
      multiplier = 2.0 / (@period + 1)
      @value = (price - @value) * multiplier + @value
    end
  end
end
