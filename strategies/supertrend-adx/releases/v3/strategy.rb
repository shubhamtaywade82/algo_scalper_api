# frozen_string_literal: true

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

class SupertrendAdxStrategy < BaseStrategy
  def call(context)
    series_1m = context.candles.call("1m")
    series_5m = context.candles.call("5m")
    return Signals::Hold.new(reason: "no_candle_data") unless series_1m&.candles&.any? && series_5m&.candles&.any?

    st_period = (params[:supertrend_period] || 10).to_i
    st_multiplier = (params[:supertrend_multiplier] || 3.0).to_f
    adx_threshold = (params[:adx_threshold] || params[:adx_min] || 20).to_i
    adx_period = (params[:adx_period] || 14).to_i

    # 1. 5m Higher Timeframe Bias
    res_5m = Indicators::Supertrend.new(series: series_5m, period: st_period, base_multiplier: st_multiplier).call
    last_idx_5m = res_5m[:line]&.rindex { |v| !v.nil? }
    return Signals::Hold.new(reason: "5m_supertrend_unavailable") unless last_idx_5m
    close_5m = series_5m.candles[last_idx_5m].close
    line_5m = res_5m[:line][last_idx_5m]
    trend_5m = res_5m[:trend] || (close_5m >= line_5m ? :bullish : :bearish)

    # 2. 1m Lower Timeframe Signal
    res_1m = Indicators::Supertrend.new(series: series_1m, period: st_period, base_multiplier: st_multiplier).call
    last_idx_1m = res_1m[:line]&.rindex { |v| !v.nil? }
    return Signals::Hold.new(reason: "1m_supertrend_unavailable") unless last_idx_1m
    close_1m = series_1m.candles[last_idx_1m].close
    line_1m = res_1m[:line][last_idx_1m]
    trend_1m = res_1m[:trend] || (close_1m >= line_1m ? :bullish : :bearish)

    # 3. ADX Filter Gating
    adx = series_1m.adx(adx_period)
    return Signals::Hold.new(reason: "adx_unavailable") if adx.nil?
    return Signals::Hold.new(reason: "adx_below_threshold(#{adx.round(1)})") if adx < adx_threshold

    # 4. Multi-Timeframe Alignment
    unless trend_1m == trend_5m
      return Signals::Hold.new(reason: "mtf_trend_mismatch(1m:#{trend_1m},5m:#{trend_5m})")
    end

    if trend_1m == :bullish && close_1m > line_1m
      Signals::BuyCall.new(confidence: 0.7, reason: "mtf_supertrend_bullish_adx_confirmed")
    elsif trend_1m == :bearish && close_1m < line_1m
      Signals::BuyPut.new(confidence: 0.7, reason: "mtf_supertrend_bearish_adx_confirmed")
    else
      Signals::Hold.new(reason: "trend_not_confirmed")
    end
  end
end

