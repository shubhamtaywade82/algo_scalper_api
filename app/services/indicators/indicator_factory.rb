# frozen_string_literal: true

module Indicators
  # Factory for creating indicator instances from configuration
  class IndicatorFactory
    class << self
      # Build indicators from configuration
      # @param series [CandleSeries] Candle series
      # @param config [Hash] Indicator configuration
      # @return [Array<BaseIndicator>] Array of indicator instances
      def build_indicators(series:, config: {})
        indicator_configs = config[:indicators] || []
        return [] if indicator_configs.empty?

        indicator_configs.map do |indicator_config|
          build_indicator(series: series, config: indicator_config, global_config: config)
        end.compact
      end

      # Build a single indicator from configuration
      # @param series [CandleSeries] Candle series
      # @param config [Hash] Indicator-specific configuration
      # @param global_config [Hash] Global configuration to merge
      # @return [BaseIndicator, nil] Indicator instance or nil if invalid
      def build_indicator(series:, config:, global_config: {})
        indicator_type = config[:type] || config[:name]
        merged_config = global_config.merge(config[:config] || {})

        case indicator_type.to_s.downcase
        when 'supertrend', 'st'
          Indicators::SupertrendIndicator.new(series: series, config: merged_config)
        when 'adx'
          Indicators::AdxIndicator.new(series: series, config: merged_config)
        when 'rsi'
          Indicators::RsiIndicator.new(series: series, config: merged_config)
        when 'macd'
          Indicators::MacdIndicator.new(series: series, config: merged_config)
        when 'trend_duration', 'trend_duration_forecast', 'tdf'
          Indicators::TrendDurationIndicator.new(series: series, config: merged_config)
        else
          Rails.logger.warn("[IndicatorFactory] Unknown indicator type: #{indicator_type}")
          nil
        end
      rescue StandardError => e
        Rails.logger.error("[IndicatorFactory] Error building indicator #{indicator_type}: #{e.class} - #{e.message}")
        nil
      end
    end
  end
end
