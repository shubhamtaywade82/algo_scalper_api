# frozen_string_literal: true

module Scalp
  # MomentumScaler — continuous underlying-momentum scaling for the trailing stop.
  #
  # PROBLEM: UnderlyingContextEvaluator's trailing feedback is binary — a single
  # weakness signal compresses the allowed drawdown by a FIXED multiplier (0.5x)
  # and everything else leaves the trail untouched. Real momentum is a spectrum:
  # a scalper wants the trail to WIDEN while the underlying is ripping (stop being
  # shaken out of a runner by one-tick pullbacks) and to TIGHTEN progressively as
  # it fades — with a hard "momentum is dead, exit now" floor instead of waiting
  # for a widened trail to be hit on a dying scalp.
  #
  # Score M ∈ [0, 1] is composed from the UnderlyingMonitor state (all existing
  # fields — no new data sources):
  #
  #   trend component (50%)  trend_score / trend_score_max, clamped to [0, 1]
  #   atr component   (35%)  atr_ratio mapped: >= 1.0 healthy (1.0),
  #                          <= atr_ratio_threshold collapse (0.0), linear between;
  #                          unknown -> 0.5 (neutral, no fabricated direction)
  #   confirmation bonus (15%)  mtf_confirm (60%) + BOS alignment (40%), each
  #                          scored 1.0 / 0.75 / 0.5 / 0.25 per state
  #
  # Multiplier mapping (linear in M):
  #   death?  M < death_threshold  -> caller exits immediately
  #   M otherwise                 -> min_multiplier + (max - min) * M
  #                                  e.g. M = 0.3 -> ~0.84x (tight-ish)
  #                                       M = 1.0 -> 1.4x   (let it breathe)
  #
  # The scaler never decides exits by itself except through death?; it REPLACES the
  # fixed tighten multiplier of UnderlyingContextEvaluator when
  # risk.underlying_context_exit.momentum_scaling.enabled is true (opt-in — the
  # legacy binary behaviour is preserved when the section is absent, matching the
  # wave-2 opt-in convention).
  #
  # Config (config/algo.yml under risk.underlying_context_exit.momentum_scaling):
  #   momentum_scaling:
  #     enabled: true
  #     death_threshold: 0.30
  #     trend_score_max: 45.0
  #     min_multiplier: 0.6
  #     max_multiplier: 1.4
  class MomentumScaler
    DEFAULTS = {
      death_threshold: 0.30,
      trend_score_max: 45.0,
      min_multiplier: 0.6,
      max_multiplier: 1.4
    }.freeze

    NUMERIC_PATTERN = /\A-?\d+(\.\d+)?\z/.freeze

    WEIGHT_TREND = 0.50
    WEIGHT_ATR = 0.35
    WEIGHT_CONFIRMATION = 0.15
    MTF_SHARE = 0.60
    BOS_SHARE = 0.40

    NEUTRAL_UNKNOWN = 0.5

    # @param cfg [Hash] the momentum_scaling config section (defaults resolved here)
    def initialize(cfg = {})
      @cfg = cfg || {}
    end

    class << self
      def from_config
        new(AlgoConfig.fetch.dig(:risk, :underlying_context_exit, :momentum_scaling) || {})
      end

      def enabled?
        raw = AlgoConfig.fetch.dig(:risk, :underlying_context_exit, :momentum_scaling)
        raw.is_a?(Hash) ? raw[:enabled] == true : false
      end
    end

    # Composite momentum score.
    # @param state [OpenStruct] UnderlyingMonitor state (trend_score, atr_ratio,
    #   atr_trend, mtf_confirm, bos_state, bos_direction)
    # @param direction [Symbol] :bullish / :bearish — the position's direction
    # @return [Float, nil] nil when the core trend signal is unavailable
    #   (score would be fabrication; caller keeps the trail untouched)
    def score(state, direction)
      return nil if state.nil? || state.trend_score.nil?

      trend = (state.trend_score.to_f / cfg_value(:trend_score_max)).clamp(0.0, 1.0)
      atr = atr_component(state)
      confirmation = (MTF_SHARE * mtf_component(state)) + (BOS_SHARE * bos_component(state, direction))

      ((WEIGHT_TREND * trend) + (WEIGHT_ATR * atr) + (WEIGHT_CONFIRMATION * confirmation)).clamp(0.0, 1.0)
    end

    # Momentum death: the scalp's engine has stalled — exit now rather than wait
    # for a (possibly widened) trail to be hit. Only meaningful when score is known.
    # @param momentum_score [Float, nil]
    # @return [Boolean]
    def death?(momentum_score)
      return false if momentum_score.nil?

      momentum_score < cfg_value(:death_threshold)
    end

    # Continuous trail multiplier for a live score. Returns exactly 1.0 for an
    # unknown score (no information -> no change).
    # @param momentum_score [Float, nil]
    # @return [Float]
    def multiplier(momentum_score)
      return 1.0 if momentum_score.nil?

      min_mult = cfg_value(:min_multiplier)
      max_mult = cfg_value(:max_multiplier)
      unless min_mult.positive? && max_mult.positive?
        raise Errors::ConfigurationError,
              "risk.underlying_context_exit.momentum_scaling min_multiplier and max_multiplier must be positive " \
              "(got min=#{min_mult}, max=#{max_mult})"
      end

      span = [max_mult - min_mult, 0.0].max
      (min_mult + (span * momentum_score.clamp(0.0, 1.0))).round(4)
    end

    private

    def atr_component(state)
      ratio = state.atr_ratio
      return NEUTRAL_UNKNOWN if ratio.nil?

      threshold = atr_ratio_threshold
      return 1.0 if ratio >= 1.0
      return 0.0 if ratio <= threshold

      (ratio - threshold) / (1.0 - threshold)
    end

    def mtf_component(state)
      state.mtf_confirm ? 1.0 : NEUTRAL_UNKNOWN
    end

    def bos_component(state, direction)
      return NEUTRAL_UNKNOWN if state.bos_state == :unknown

      if state.bos_state == :broken
        # Evaluator's hard exit handles breaks AGAINST the position before the
        # scaler ever runs; a break in FAVOUR is displacement in our direction.
        bos_in_favour?(state, direction) ? 1.0 : 0.25
      else
        0.75 # intact structure
      end
    end

    def bos_in_favour?(state, direction)
      (direction == :bullish && state.bos_direction == :bullish) ||
        (direction == :bearish && state.bos_direction == :bearish)
    end

    # The ATR collapse threshold is shared with the evaluator's own config so the
    # scaler's 0.0 anchor means the same thing as "ATR collapsing" there.
    def atr_ratio_threshold
      raw = AlgoConfig.fetch.dig(:risk, :underlying_context_exit, :atr_ratio_threshold)
      return 0.65 if raw.nil?
      return raw.to_f if raw.is_a?(Numeric)
      return raw.to_f if raw.is_a?(String) && raw.match?(NUMERIC_PATTERN)

      raise Errors::ConfigurationError,
            "risk.underlying_context_exit.atr_ratio_threshold must be numeric (got #{raw.inspect})"
    end

    def cfg_value(key)
      raw = @cfg[key]
      return DEFAULTS[key].to_f if raw.nil?
      return raw.to_f if raw.is_a?(Numeric)
      return raw.to_f if raw.is_a?(String) && raw.match?(NUMERIC_PATTERN)

      raise Errors::ConfigurationError,
            "risk.underlying_context_exit.momentum_scaling.#{key} must be numeric (got #{raw.inspect})"
    end
  end
end
