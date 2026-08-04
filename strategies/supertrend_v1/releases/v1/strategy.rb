# frozen_string_literal: true

# Supertrend V1 — Multi-Timeframe (1m + 5m) Supertrend + ADX strategy.
#
# Uses 1m candles for execution / signal generation and 5m candles for higher timeframe trend bias.
# Only enters when 1m trend matches 5m trend and ADX filter on 1m passes.
class SupertrendV1 < Strategies::Base
  class << self
    def timeframes = %w[1m 5m]
    def instruments = %w[NIFTY BANKNIFTY SENSEX]
    def params_schema
      {
        supertrend_period: { type: "integer", default: 10 },
        supertrend_multiplier: { type: "float", default: 2.0 },
        adx_min: { type: "float", default: 20.0 }
      }
    end
  end

  def call(context)
    series_1m = context.candles.call("1m")
    series_5m = context.candles.call("5m")
    return Signals::Hold.new(reason: "no_candle_data") unless series_1m&.candles&.any? && series_5m&.candles&.any?

    # 1. Higher Timeframe (5m) Bias
    st_5m = calculate_supertrend(series_5m)
    return Signals::Hold.new(reason: "5m_supertrend_unavailable") if st_5m[:trend].nil?

    trend_5m = resolve_trend(series_5m, st_5m)
    return Signals::Hold.new(reason: "5m_trend_none") if trend_5m == :none

    # 2. Lower Timeframe (1m) Signal
    st_1m = calculate_supertrend(series_1m)
    return Signals::Hold.new(reason: "1m_supertrend_unavailable") if st_1m[:trend].nil?

    trend_1m = resolve_trend(series_1m, st_1m)
    return Signals::Hold.new(reason: "1m_trend_none") if trend_1m == :none

    # 3. ADX Filter Gating (1m)
    adx = series_1m.adx(14)
    return Signals::Hold.new(reason: "adx_unavailable") if adx.nil?
    return Signals::Hold.new(reason: "adx_below_min(#{adx.round(1)})") if adx < params[:adx_min]

    # 4. Multi-Timeframe Alignment Check
    unless trend_1m == trend_5m
      return Signals::Hold.new(reason: "mtf_trend_mismatch(1m:#{trend_1m},5m:#{trend_5m})")
    end

    direction = trend_1m == :long ? :bullish : :bearish
    confidence = compute_confidence(direction, adx, st_1m)

    case direction
    when :bullish
      Signals::BuyCall.new(confidence: confidence,
                           reason: "mtf_supertrend_bullish_adx_#{adx.round(1)}")
    when :bearish
      Signals::BuyPut.new(confidence: confidence,
                          reason: "mtf_supertrend_bearish_adx_#{adx.round(1)}")
    end
  end

  private

  def calculate_supertrend(series)
    result = Indicators::Supertrend.new(
      series: series,
      period: params[:supertrend_period],
      base_multiplier: params[:supertrend_multiplier]
    ).call

    {
      line: result[:line],
      trend: result[:trend],
      last_value: result[:last_value]
    }
  rescue StandardError
    { line: nil, trend: nil, last_value: nil }
  end

  def resolve_trend(series, st)
    return st[:trend] == :bullish ? :long : :short if st[:trend].present?

    last_valid_idx = st[:line]&.rindex { |v| !v.nil? }
    return :none unless last_valid_idx

    close = series.candles[last_valid_idx]&.close
    line_val = st[:line][last_valid_idx]
    return :none unless close && line_val

    close >= line_val ? :long : :short
  end

  def compute_confidence(direction, adx, st)
    score = 0.50

    score += case adx
             when 0...15 then 0.0
             when 15...20 then 0.10
             when 20...30 then 0.20
             else 0.30
             end

    if st[:last_value]
      score += [st[:last_value] / 1000.0, 0.10].min
    end

    [score, 1.0].min
  end
end

