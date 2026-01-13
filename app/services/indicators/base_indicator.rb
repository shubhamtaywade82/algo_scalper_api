# frozen_string_literal: true

module Indicators
  # Base interface for all indicators
  # All indicators must implement this interface
  class BaseIndicator
    attr_reader :series, :config

    def initialize(series:, config: {})
      @series = series
      @config = config
      @cached_result = nil
      @calculated = false
    end

    # Calculate indicator value at given index
    # Must return a hash with at least:
    #   - :value [Numeric, Hash, Symbol] - The indicator value/result
    #   - :direction [Symbol] - :bullish, :bearish, or :neutral
    #   - :confidence [Numeric] - Confidence score 0-100
    # Returns nil if calculation is not possible
    def calculate_at(index)
      raise NotImplementedError, "#{self.class} must implement #calculate_at"
    end

    # Check if indicator is ready (enough data available)
    # Returns true if indicator can be calculated at given index
    def ready?(index)
      raise NotImplementedError, "#{self.class} must implement #ready?"
    end

    # Get minimum required candles for this indicator
    def min_required_candles
      raise NotImplementedError, "#{self.class} must implement #min_required_candles"
    end

    # Get indicator name for logging/debugging
    def name
      class_name = self.class.name.split('::').last
      # Convert CamelCase to snake_case
      # Handle both ActiveSupport's underscore and manual conversion
      if class_name.respond_to?(:underscore)
        class_name.underscore
      else
        class_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                  .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                  .downcase
      end
    end

    # Check if trading hours filter should be applied
    def trading_hours?(candle)
      return true unless config[:trading_hours_filter]

      ist_time = candle.timestamp.in_time_zone('Asia/Kolkata')
      hour = ist_time.hour
      minute = ist_time.min

      # Default: 10:00 AM - 2:30 PM IST
      return false if hour < 10
      return false if hour > 14
      return false if hour == 14 && minute > 30

      true
    end

    protected

    def cache_result(result)
      @cached_result = result
      @calculated = true
    end

    def cached_result
      @cached_result if @calculated
    end
  end
end
