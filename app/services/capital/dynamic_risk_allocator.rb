# frozen_string_literal: true

module Capital
  # Dynamic risk allocator for NEMESIS V3
  # Maps index + trend strength → risk_pct for position sizing
  # Scales base risk based on trend_score (0-21)
  class DynamicRiskAllocator
    # Trend score range (after removing volume: 0-21)
    MIN_TREND_SCORE = 0.0
    MAX_TREND_SCORE = 21.0

    # Risk scaling multipliers
    # Low trend (0-7): 0.5x base risk
    # Medium trend (7-14): 1.0x base risk
    # High trend (14-21): 1.5x base risk (capped)
    MIN_RISK_MULTIPLIER = 0.5
    MAX_RISK_MULTIPLIER = 1.5
    NEUTRAL_TREND_THRESHOLD = 7.0
    HIGH_TREND_THRESHOLD = 14.0

    attr_reader :config

    def initialize(config: {})
      @config = config
    end

    # Calculate risk percentage based on index and trend score
    # @param index_key [Symbol, String] Index key (e.g., :NIFTY, :BANKNIFTY)
    # @param trend_score [Float, nil] Trend score from TrendScorer (0-21)
    # @return [Float] Risk percentage (0.0 to 1.0)
    def risk_pct_for(index_key:, trend_score: nil)
      base_risk = base_risk_for_index(index_key)
      return base_risk unless trend_score

      scaled_risk = scale_by_trend(trend_score, base_risk)
      cap_risk(scaled_risk, base_risk)
    rescue StandardError => e
      Rails.logger.error("[DynamicRiskAllocator] Error calculating risk_pct: #{e.class} - #{e.message}")
      # Fallback to default base risk (0.03 = 3%) to avoid infinite recursion
      default_base_risk = 0.03
      trend_score ? scale_by_trend(trend_score, default_base_risk) : default_base_risk
    end

    private

    # Get base risk percentage for index
    # @param index_key [Symbol, String] Index key
    # @return [Float] Base risk percentage from deployment policy
    def base_risk_for_index(index_key)
      # Check for index-specific override in config first
      index_override = @config.dig(:indices, index_key.to_sym, :risk_pct) ||
                       @config.dig(:indices, index_key.to_s, :risk_pct)
      return index_override if index_override

      # Get current balance to determine capital band
      balance = Capital::Allocator.available_cash.to_f
      policy = Capital::Allocator.deployment_policy(balance)

      policy[:risk_per_trade_pct]
    rescue StandardError => e
      Rails.logger.warn("[DynamicRiskAllocator] Error getting base risk: #{e.class} - #{e.message}")
      # Fallback to default base risk
      0.03
    end

    # Scale base risk by trend score
    # @param trend_score [Float] Trend score (0-21)
    # @param base_risk [Float] Base risk percentage
    # @return [Float] Scaled risk percentage
    def scale_by_trend(trend_score, base_risk)
      # Normalize trend_score to 0-1 range
      normalized_score = normalize_trend_score(trend_score)

      # Calculate multiplier based on normalized score
      # Linear interpolation: 0.0 → 0.5x, 0.5 → 1.0x, 1.0 → 1.5x
      multiplier = if normalized_score <= 0.5
                     # Low to medium: 0.5x to 1.0x
                     MIN_RISK_MULTIPLIER + (normalized_score * 2.0 * (1.0 - MIN_RISK_MULTIPLIER))
                   else
                     # Medium to high: 1.0x to 1.5x
                     1.0 + ((normalized_score - 0.5) * 2.0 * (MAX_RISK_MULTIPLIER - 1.0))
                   end

      base_risk * multiplier
    end

    # Normalize trend score to 0-1 range
    # @param trend_score [Float] Trend score (0-21)
    # @return [Float] Normalized score (0.0 to 1.0)
    def normalize_trend_score(trend_score)
      return 0.0 unless trend_score&.positive?

      # Clamp to valid range
      clamped = trend_score.clamp(MIN_TREND_SCORE, MAX_TREND_SCORE)

      # Normalize to 0-1
      clamped / MAX_TREND_SCORE
    end

    # Cap risk to reasonable bounds
    # @param scaled_risk [Float] Scaled risk percentage
    # @param base_risk [Float] Base risk percentage
    # @return [Float] Capped risk percentage
    def cap_risk(scaled_risk, base_risk)
      # Cap at 2x base risk (safety limit)
      max_risk = base_risk * 2.0

      # Cap at 10% absolute maximum (safety limit)
      absolute_max = 0.10

      [[scaled_risk, max_risk].min, absolute_max].min
    end
  end
end
