# frozen_string_literal: true

# Supertrend V1 — the alpha logic extracted from Signal::Engine.
#
# Evaluates 1m candles and returns Signals::BuyCall / BuyPut / Hold
# based on Supertrend direction, ADX filter, and closing-price
# confirmation against the supertrend line.
#
# Platform concerns (EntryGuard, option-chain analysis, TradingSignal
# persistence, LTP confirmation) live in the manager — this plugin is
# a pure decision function.
class SupertrendV1 < Strategies::Base
  class << self
    def timeframes = %w[1m]
    def instruments = %w[NIFTY BANKNIFTY SENSEX]
    def params_schema = {
      supertrend_period: { type: "integer", default: 10 },
      supertrend_multiplier: { type: "float", default: 2.0 },
      adx_min: { type: "float", default: 20.0 }
    }
  end

  def call(context)
    series = context.candles.call("1m")
    return Signals::Hold.new(reason: "no_candle_data") unless series&.candles&.any?

    st = calculate_supertrend(series)
    return Signals::Hold.new(reason: "supertrend_unavailable") if st[:trend].nil?

    adx = series.adx(14)
    return Signals::Hold.new(reason: "adx_unavailable") if adx.nil?
    return Signals::Hold.new(reason: "adx_below_min(#{adx.round(1)})") if adx < params[:adx_min]

    trend_direction = resolve_trend(series, st)
    return Signals::Hold.new(reason: "trend_none") if trend_direction == :none

    direction = (trend_direction == :long) ? :bullish : :bearish
    confidence = compute_confidence(direction, adx, st)

    case direction
    when :bullish
      Signals::BuyCall.new(confidence: confidence,
                           reason: "supertrend_bullish_adx_#{adx.round(1)}")
    when :bearish
      Signals::BuyPut.new(confidence: confidence,
                          reason: "supertrend_bearish_adx_#{adx.round(1)}")
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
    last_valid_idx = st[:line].rindex { |v| !v.nil? }
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
