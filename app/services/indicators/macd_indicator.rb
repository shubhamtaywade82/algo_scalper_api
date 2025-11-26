# frozen_string_literal: true

module Indicators
  # MACD (Moving Average Convergence Divergence) indicator wrapper
  class MacdIndicator < BaseIndicator
    def initialize(series:, config: {})
      super
      @fast_period = config[:fast_period] || 12
      @slow_period = config[:slow_period] || 26
      @signal_period = config[:signal_period] || 9
    end

    def min_required_candles
      @slow_period + @signal_period
    end

    def ready?(index)
      index >= min_required_candles
    end

    def calculate_at(index)
      return nil unless ready?(index)
      return nil unless trading_hours?(series.candles[index])

      partial_series = create_partial_series(index)
      macd_result = partial_series&.macd(@fast_period, @slow_period, @signal_period)
      return nil if macd_result.nil?

      direction = determine_direction(macd_result)
      confidence = calculate_confidence(macd_result, direction)

      {
        value: macd_result,
        direction: direction,
        confidence: confidence
      }
    end

    private

    def create_partial_series(index)
      partial_series = CandleSeries.new(symbol: series.symbol, interval: series.interval)
      series.candles[0..index].each { |candle| partial_series.add_candle(candle) }
      partial_series
    end

    def determine_direction(macd_result)
      macd_line = macd_result[:macd] || 0
      signal_line = macd_result[:signal] || 0
      histogram = macd_result[:histogram] || 0

      # Bullish: MACD crosses above signal and histogram is positive
      if macd_line > signal_line && histogram > 0
        :bullish
      # Bearish: MACD crosses below signal and histogram is negative
      elsif macd_line < signal_line && histogram < 0
        :bearish
      else
        :neutral
      end
    end

    def calculate_confidence(macd_result, direction)
      base = 40
      histogram = macd_result[:histogram] || 0

      case direction
      when :bullish
        base += 20 if histogram > 0
        base += 20 if macd_result[:macd] > macd_result[:signal]
        base += 10 if histogram.abs > 0.5 # Strong signal
      when :bearish
        base += 20 if histogram < 0
        base += 20 if macd_result[:macd] < macd_result[:signal]
        base += 10 if histogram.abs > 0.5 # Strong signal
      end

      [base, 100].min
    end
  end
end
