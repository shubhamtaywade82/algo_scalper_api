# frozen_string_literal: true

module Validators
  class MomentumGate
    MIN_CONFIRMATIONS = 1

    def initialize(underlying:, direction:, series:, supertrend_result:)
      @underlying = underlying
      @direction = direction
      @series = series
      @supertrend_result = supertrend_result
    end

    def check
      st_ok = supertrend_aligned?
      return { pass: false, reason: "Supertrend not aligned with #{@direction} direction" } unless st_ok

      momentum = Signal::MomentumValidator.validate(
        instrument: nil,
        series: @series,
        direction: @direction,
        min_confirmations: MIN_CONFIRMATIONS
      )

      {
        pass: momentum.valid,
        score: momentum.score,
        factors: momentum.factors,
        signal_type: momentum.valid ? :momentum_confirmed : :no_momentum,
        reason: momentum.valid ? "OK" : momentum.reasons.join("; ")
      }
    end

    private

    def supertrend_aligned?
      return false if @supertrend_result.blank?

      st_direction = SupertrendTrend.direction(
        series: @series,
        supertrend_result: @supertrend_result
      )
      return false if st_direction == :none

      case @direction
      when :bullish then st_direction == :long
      when :bearish then st_direction == :short
      else false
      end
    end
  end
end
