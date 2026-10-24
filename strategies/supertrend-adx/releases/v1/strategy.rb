# frozen_string_literal: true

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

class SupertrendAdxStrategy < BaseStrategy
  def call(context)
    series = context.candles.call("5m")
    return Signals::Hold.new(reason: "no_candle_data") unless series&.candles&.any?

    st_period = (params[:supertrend_period] || 10).to_i
    st_multiplier = (params[:supertrend_multiplier] || 3.0).to_f
    adx_threshold = (params[:adx_threshold] || 25).to_i
    adx_period = (params[:adx_period] || 14).to_i

    result = Indicators::Supertrend.new(series: series, period: st_period, base_multiplier: st_multiplier).call
    last_idx = result[:line]&.rindex { |v| !v.nil? }
    return Signals::Hold.new(reason: "supertrend_unavailable") unless last_idx

    adx = series.adx(adx_period)
    return Signals::Hold.new(reason: "adx_unavailable") if adx.nil?
    return Signals::Hold.new(reason: "adx_below_threshold(#{adx.round(1)})") if adx < adx_threshold

    close = series.candles[last_idx].close
    line_value = result[:line][last_idx]

    if result[:trend] == :bullish && close > line_value
      Signals::BuyCall.new(confidence: 0.7, reason: "supertrend_bullish_adx_confirmed")
    elsif result[:trend] == :bearish && close < line_value
      Signals::BuyPut.new(confidence: 0.7, reason: "supertrend_bearish_adx_confirmed")
    else
      Signals::Hold.new(reason: "trend_not_confirmed")
    end
  end
end
