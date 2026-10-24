# frozen_string_literal: true

module Indicators
  # ADX (Average Directional Index) indicator wrapper
  class AdxIndicator < BaseIndicator
    def initialize(series:, config: {})
      super
      @period = config[:period] || 14
      # Allow threshold config to override min_strength
      threshold_config = Indicators::ThresholdConfig.merge_with_thresholds(:adx, @config)
      @min_strength = threshold_config[:min_strength] || config[:min_strength] || 20
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

      # Use existing CandleSeries#adx method (uses TechnicalAnalysis gem)
      # Create partial series up to current index for accurate calculation at that point
      partial_series = create_partial_series(index)
      adx_value = partial_series.adx(@period)
      return nil if adx_value.nil? || adx_value < @min_strength

      # ADX doesn't provide direction directly, but we can infer from trend
      direction = infer_direction_from_price(index)
      confidence = calculate_confidence(adx_value)

      {
        value: adx_value,
        direction: direction,
        confidence: confidence
      }
    end

    private

    def create_partial_series(index)
      # Create partial series for calculation at specific index
      # Uses existing CandleSeries#adx which leverages TechnicalAnalysis gem
      partial_series = CandleSeries.new(symbol: series.symbol, interval: series.interval)
      series.candles[0..index].each { |candle| partial_series.add_candle(candle) }
      partial_series
    end

    def infer_direction_from_price(index)
      # Infer direction from recent price movement
      return :neutral if index < 2

      candles = series.candles[0..index]
      recent_closes = candles.last(3).filter_map(&:close)

      return :neutral if recent_closes.size < 2

      if recent_closes.last > recent_closes.first
        :bullish
      elsif recent_closes.last < recent_closes.first
        :bearish
      else
        :neutral
      end
    end

    def calculate_confidence(adx_value)
      # Allow threshold config to override confidence base
      threshold_config = Indicators::ThresholdConfig.merge_with_thresholds(:adx, config)
      base = threshold_config[:confidence_base] || 50
      base += 20 if adx_value >= @min_strength
      base += 15 if adx_value >= 30
      base += 10 if adx_value >= 40
      [base, 100].min
    end
  end
end
