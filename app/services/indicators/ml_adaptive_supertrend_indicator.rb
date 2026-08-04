# frozen_string_literal: true

module Indicators
  # ML Adaptive SuperTrend indicator wrapper
  class MlAdaptiveSupertrendIndicator < BaseIndicator
    def initialize(series:, config: {})
      super
      @mast_service = nil
      @mast_result = nil
    end

    def min_required_candles
      period = config[:atr_len] || 10
      training = config[:training_period] || 100
      [period, training].max + 1
    end

    def ready?(index)
      index >= min_required_candles
    end

    def calculate_at(index)
      return nil unless ready?(index)
      return nil unless trading_hours?(series.candles[index])

      # Calculate indicator once for the entire series (cached)
      calculate_mast_once unless @mast_result

      return nil if @mast_result.nil? || @mast_result[:direction].nil?

      direction_at = @mast_result[:direction][index]
      regime_at = @mast_result[:regimes][index]
      st_value = @mast_result[:super_trend][index]

      return nil if st_value.nil? || direction_at.nil?

      {
        value: st_value,
        direction: (direction_at == -1 ? :bullish : :bearish),
        confidence: calculate_confidence(direction_at, index),
        regime: regime_name(regime_at),
        raw_result: @mast_result
      }
    end

    private

    def calculate_mast_once
      @mast_service = Indicators::MlAdaptiveSupertrend.new(series: series, config: config)
      @mast_result = @mast_service.call
    end

    def calculate_confidence(direction, index)
      # Base confidence for ML Adaptive SuperTrend
      base = 65

      # Boost confidence if trend is consistent for a few bars
      if index > 3
        prev_dirs = @mast_result[:direction][(index - 3)..index]
        if prev_dirs.uniq.size == 1
          base += 15
        end
      end

      # Boost based on volatility regime?
      # High vol regimes might have lower confidence but better profit potential
      # Let's keep it simple for now
      [base, 100].min
    end

    def regime_name(regime)
      case regime
      when 0 then :high_volatility
      when 1 then :medium_volatility
      when 2 then :low_volatility
      else :unknown
      end
    end
  end
end
