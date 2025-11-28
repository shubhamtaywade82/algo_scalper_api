# frozen_string_literal: true

module Indicators
  # RSI (Relative Strength Index) indicator wrapper
  class RsiIndicator < BaseIndicator
    def initialize(series:, config: {})
      super
      @period = config[:period] || 14
      # Allow threshold config to override oversold/overbought levels
      threshold_config = Indicators::ThresholdConfig.merge_with_thresholds(:rsi, @config)
      @oversold = threshold_config[:oversold] || config[:oversold] || 30
      @overbought = threshold_config[:overbought] || config[:overbought] || 70
    end

    def min_required_candles
      @period + 1
    end

    def ready?(index)
      index >= min_required_candles
    end

    def calculate_at(index)
      return nil unless ready?(index)
      return nil unless trading_hours?(series.candles[index])

      # Use existing CandleSeries#rsi method (uses RubyTechnicalAnalysis gem)
      # Create partial series up to current index for accurate calculation at that point
      partial_series = create_partial_series(index)
      rsi_value = partial_series.rsi(@period)
      return nil if rsi_value.nil?

      direction = determine_direction(rsi_value)
      confidence = calculate_confidence(rsi_value, direction)

      {
        value: rsi_value,
        direction: direction,
        confidence: confidence
      }
    end

    private

    def create_partial_series(index)
      # Create partial series for calculation at specific index
      # Uses existing CandleSeries#rsi which leverages RubyTechnicalAnalysis gem
      partial_series = CandleSeries.new(symbol: series.symbol, interval: series.interval)
      series.candles[0..index].each { |candle| partial_series.add_candle(candle) }
      partial_series
    end

    def determine_direction(rsi_value)
      if rsi_value < @oversold
        :bullish # Oversold - potential upward move
      elsif rsi_value > @overbought
        :bearish # Overbought - potential downward move
      else
        :neutral
      end
    end

    def calculate_confidence(rsi_value, direction)
      # Allow threshold config to override confidence base
      threshold_config = Indicators::ThresholdConfig.merge_with_thresholds(:rsi, config)
      base = threshold_config[:confidence_base] || 40

      case direction
      when :bullish
        # More oversold = higher confidence
        base += 30 if rsi_value < 25
        base += 20 if rsi_value < @oversold
      when :bearish
        # More overbought = higher confidence
        base += 30 if rsi_value > 75
        base += 20 if rsi_value > @overbought
      end

      [base, 100].min
    end
  end
end
