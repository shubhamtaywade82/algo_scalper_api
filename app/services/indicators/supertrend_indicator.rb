# frozen_string_literal: true

module Indicators
  # Supertrend indicator wrapper
  class SupertrendIndicator < BaseIndicator
    def initialize(series:, config: {})
      super
      @supertrend_service = nil
      @supertrend_result = nil
    end

    def min_required_candles
      config[:period] || config.fetch(:supertrend_cfg, {})[:period] || 7
    end

    def ready?(index)
      index >= min_required_candles
    end

    def calculate_at(index)
      return nil unless ready?(index)
      return nil unless trading_hours?(series.candles[index])

      # Calculate Supertrend once for the entire series (cached)
      calculate_supertrend_once unless @supertrend_result

      return nil if @supertrend_result.nil? || @supertrend_result[:trend].nil?

      trend_at_index = get_trend_at_index(index)
      return nil if trend_at_index.nil?

      {
        value: @supertrend_result[:line][index],
        direction: trend_at_index,
        confidence: calculate_confidence(trend_at_index),
        raw_result: @supertrend_result
      }
    end

    private

    def calculate_supertrend_once
      supertrend_cfg = config[:supertrend_cfg] || {
        period: config[:period] || 7,
        multiplier: config[:multiplier] || 3
      }

      @supertrend_service = Indicators::Supertrend.new(series: series, **supertrend_cfg)
      @supertrend_result = @supertrend_service.call
    end

    def get_trend_at_index(index)
      return nil if @supertrend_result.nil?
      return nil if index >= @supertrend_result[:line].size

      close = series.candles[index].close
      supertrend_value = @supertrend_result[:line][index]
      return nil if close.nil? || supertrend_value.nil?

      close >= supertrend_value ? :bullish : :bearish
    end

    def calculate_confidence(trend)
      # Base confidence for Supertrend
      base = 60
      base += 20 if @supertrend_result[:trend] == trend
      [base, 100].min
    end
  end
end
