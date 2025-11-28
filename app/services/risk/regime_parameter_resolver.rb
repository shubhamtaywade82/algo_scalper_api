# frozen_string_literal: true

module Risk
  # Resolves trading parameters (SL, TP, Trail, Timeout) based on volatility regime
  # and market condition for a specific index
  class RegimeParameterResolver < ApplicationService
    attr_reader :index_key, :regime, :condition, :parameters

    def initialize(index_key:, regime: nil, condition: nil)
      @index_key = index_key.to_s.upcase
      @regime = regime
      @condition = condition
      @parameters = nil
    end

    def call
      # Auto-detect regime and condition if not provided
      detect_regime_and_condition unless @regime && @condition

      # Resolve parameters
      @parameters = resolve_parameters

      {
        index_key: @index_key,
        regime: @regime,
        condition: @condition,
        parameters: @parameters
      }
    rescue StandardError => e
      Rails.logger.error("[RegimeParameterResolver] Error for #{@index_key}: #{e.class} - #{e.message}")
      default_parameters
    end

    # Get specific parameter value (uses midpoint of range)
    def sl_pct
      range = @parameters&.dig(:sl_pct_range)
      return nil unless range&.is_a?(Array) && range.size == 2

      (range[0] + range[1]) / 2.0
    end

    def tp_pct
      range = @parameters&.dig(:tp_pct_range)
      return nil unless range&.is_a?(Array) && range.size == 2

      (range[0] + range[1]) / 2.0
    end

    def trail_pct
      range = @parameters&.dig(:trail_pct_range)
      return nil unless range&.is_a?(Array) && range.size == 2

      (range[0] + range[1]) / 2.0
    end

    def timeout_minutes
      range = @parameters&.dig(:timeout_minutes)
      return nil unless range&.is_a?(Array) && range.size == 2

      (range[0] + range[1]) / 2.0
    end

    # Get random value within range (for dynamic parameter selection)
    def sl_pct_random
      range = @parameters&.dig(:sl_pct_range)
      return nil unless range&.is_a?(Array) && range.size == 2

      rand(range[0]..range[1])
    end

    def tp_pct_random
      range = @parameters&.dig(:tp_pct_range)
      return nil unless range&.is_a?(Array) && range.size == 2

      rand(range[0]..range[1])
    end

    def trail_pct_random
      range = @parameters&.dig(:trail_pct_range)
      return nil unless range&.is_a?(Array) && range.size == 2

      rand(range[0]..range[1])
    end

    def timeout_minutes_random
      range = @parameters&.dig(:timeout_minutes)
      return nil unless range&.is_a?(Array) && range.size == 2

      rand(range[0]..range[1]).round
    end

    private

    def detect_regime_and_condition
      # Detect volatility regime
      regime_result = VolatilityRegimeService.call
      @regime = regime_result[:regime]

      # Detect market condition
      condition_result = MarketConditionService.call(index_key: @index_key)
      @condition = condition_result[:condition]

      # If condition is neutral, default to bullish for CE trades
      @condition = :bullish if @condition == :neutral
    end

    def resolve_parameters
      config = fetch_config
      return default_parameters unless config[:enabled]

      index_params = config.dig(:parameters, @index_key.to_sym)
      return default_parameters unless index_params

      regime_key = regime_config_key(@regime)
      return default_parameters unless regime_key

      regime_params = index_params[regime_key]
      return default_parameters unless regime_params

      condition_key = @condition.to_sym
      condition_params = regime_params[condition_key]
      return default_parameters unless condition_params

      {
        sl_pct_range: condition_params[:sl_pct_range],
        tp_pct_range: condition_params[:tp_pct_range],
        trail_pct_range: condition_params[:trail_pct_range],
        timeout_minutes: condition_params[:timeout_minutes]
      }
    end

    def regime_config_key(regime)
      case regime
      when :high then :high_volatility
      when :medium then :medium_volatility
      when :low then :low_volatility
      else nil
      end
    end

    def fetch_config
      AlgoConfig.fetch.dig(:risk, :volatility_regimes) || {}
    rescue StandardError
      { enabled: false }
    end

    def default_parameters
      # Fallback to default risk config if regime-based params not available
      risk_config = AlgoConfig.fetch[:risk] || {}
      {
        sl_pct_range: [risk_config[:sl_pct] || 30, risk_config[:sl_pct] || 30],
        tp_pct_range: [risk_config[:tp_pct] || 60, risk_config[:tp_pct] || 60],
        trail_pct_range: [5.0, 5.0],
        timeout_minutes: [10, 10]
      }
    end
  end
end
