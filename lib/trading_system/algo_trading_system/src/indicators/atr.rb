# frozen_string_literal: true

require_relative 'indicator_base'

module Indicators
  # Average True Range
  class Atr < IndicatorBase
    attr_reader :period, :value

    def initialize(period: 14)
      super()
      @period = period
      @prev_close = nil
      @tr_history = []
      @value = nil
      @count = 0
    end

    def update(candle)
      @count += 1
      tr = calculate_true_range(candle)
      @prev_close = candle.close

      process_true_range(tr)
    end

    def ready?
      @count >= @period
    end

    private

    def calculate_true_range(candle)
      return candle.high - candle.low if @prev_close.nil?

      [
        candle.high - candle.low,
        (candle.high - @prev_close).abs,
        (candle.low - @prev_close).abs
      ].max
    end

    def process_true_range(tr)
      if @count <= @period
        collect_initial_samples(tr)
        return
      end

      smooth_true_range(tr)
    end

    def collect_initial_samples(tr)
      @tr_history << tr
      return if @count < @period

      @value = @tr_history.sum / @period.to_f
    end

    def smooth_true_range(tr)
      @value = ((@value * (@period - 1)) + tr) / @period.to_f
    end
  end
end
