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

      # Use existing CandleSeries#macd method (uses RubyTechnicalAnalysis gem)
      # Create partial series up to current index for accurate calculation at that point
      partial_series = create_partial_series(index)
      macd_result = partial_series.macd(@fast_period, @slow_period, @signal_period)
      return nil if macd_result.nil?

      # CandleSeries#macd returns [macd, signal, histogram] array
      macd_array = macd_result.is_a?(Array) ? macd_result : [macd_result]
      return nil if macd_array.size < 3

      macd_line = macd_array[0] || 0
      signal_line = macd_array[1] || 0
      histogram = macd_array[2] || 0

      direction = determine_direction(macd_line, signal_line, histogram)
      confidence = calculate_confidence(macd_line, signal_line, histogram, direction)

      {
        value: { macd: macd_line, signal: signal_line, histogram: histogram },
        direction: direction,
        confidence: confidence
      }
    end

    private

    def create_partial_series(index)
      # Create partial series for calculation at specific index
      # Uses existing CandleSeries#macd which leverages RubyTechnicalAnalysis gem
      partial_series = CandleSeries.new(symbol: series.symbol, interval: series.interval)
      series.candles[0..index].each { |candle| partial_series.add_candle(candle) }
      partial_series
    end

    def determine_direction(macd_line, signal_line, histogram)
      # Bullish: MACD crosses above signal and histogram is positive
      if macd_line > signal_line && histogram.positive?
        :bullish
      # Bearish: MACD crosses below signal and histogram is negative
      elsif macd_line < signal_line && histogram.negative?
        :bearish
      else
        :neutral
      end
    end

    def calculate_confidence(macd_line, signal_line, histogram, direction)
      base = 40

      case direction
      when :bullish
        base += 20 if histogram.positive?
        base += 20 if macd_line > signal_line
        base += 10 if histogram.abs > 0.5 # Strong signal
      when :bearish
        base += 20 if histogram.negative?
        base += 20 if macd_line < signal_line
        base += 10 if histogram.abs > 0.5 # Strong signal
      end

      [base, 100].min
    end
  end
end
