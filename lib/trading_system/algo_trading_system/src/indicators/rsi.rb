# frozen_string_literal: true

require_relative 'indicator_base'

module Indicators
  # Relative Strength Index
  class Rsi < IndicatorBase
    attr_reader :period, :value

    def initialize(period: 14)
      super()
      @period = period
      @history = []
      @gains = []
      @losses = []
      @avg_gain = nil
      @avg_loss = nil
      @value = nil
    end

    def update(candle)
      price = candle.close
      @history << price

      return if too_few_prices?

      change = price - @history[-2]
      process_change(change)
      @history.shift if @history.size > @period + 1
    end

    def ready?
      @history.size > @period
    end

    private

    def too_few_prices?
      @history.size < 2
    end

    def process_change(change)
      gain = change.positive? ? change : 0.0
      loss = change.negative? ? -change : 0.0

      if @history.size <= @period + 1
        collect_initial_samples(gain, loss)
        return
      end

      smooth_averages(gain, loss)
      calculate_rsi
    end

    def collect_initial_samples(gain, loss)
      @gains << gain
      @losses << loss

      return if @history.size <= @period

      @avg_gain = @gains.sum / @period.to_f
      @avg_loss = @losses.sum / @period.to_f
      calculate_rsi
    end

    def smooth_averages(gain, loss)
      @avg_gain = ((@avg_gain * (@period - 1)) + gain) / @period.to_f
      @avg_loss = ((@avg_loss * (@period - 1)) + loss) / @period.to_f
    end

    def calculate_rsi
      return if @avg_gain.nil? || @avg_loss.nil?

      if @avg_loss.zero?
        @value = 100.0
        return
      end

      rs = @avg_gain / @avg_loss
      @value = 100.0 - (100.0 / (1.0 + rs))
    end
  end
end
