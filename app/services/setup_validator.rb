# frozen_string_literal: true

class SetupValidator
  Result = Struct.new(:valid, :reason, :metadata)

  def initialize(underlying:, direction:, series:, supertrend_result:, index_cfg:)
    @underlying = underlying
    @direction = direction
    @series = series
    @supertrend_result = supertrend_result
    @index_cfg = index_cfg
  end

  def valid?
    vol = Validators::VolatilityGate.new(@underlying).check
    unless vol[:pass]
      return Result.new(valid: false, reason: "volatility_gate: #{vol[:reason]}", metadata: { iv_percentile: vol[:percentile] })
    end

    mom = Validators::MomentumGate.new(
      underlying: @underlying, direction: @direction,
      series: @series, supertrend_result: @supertrend_result
    ).check
    unless mom[:pass]
      return Result.new(valid: false, reason: "momentum_gate: #{mom[:reason]}", metadata: { momentum_score: mom[:score] })
    end

    liq = Validators::LiquidityGate.new(
      underlying: @underlying, direction: @direction, index_cfg: @index_cfg
    ).check
    unless liq[:pass]
      return Result.new(valid: false, reason: "liquidity_gate: #{liq[:reason]}", metadata: { spread: liq[:spread] })
    end

    Result.new(
      valid: true, reason: "OK",
      metadata: {
        iv_percentile: vol[:percentile],
        momentum_score: mom[:score],
        strike: liq[:strike],
        spread: liq[:spread]
      }
    )
  end
end
