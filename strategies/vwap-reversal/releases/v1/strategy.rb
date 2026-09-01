# frozen_string_literal: true

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

# VWAP + RSI pullback, per the doc's community-consensus design (Strategy 2C) and Stage 2
# satellite recommendation: only trade once VWAP has established a clear slope, buy CE on
# pullbacks to VWAP in an uptrend / PE on rallies to VWAP in a downtrend, require RSI in the
# neutral 40-60 zone (a healthy pullback, not an exhaustion extreme) plus a confirming candle,
# stop just beyond VWAP, target the prior intraday swing at a minimum 1.5:1. Hard no-trade
# block 11:00-13:30 (the midday theta/chop dead-zone every strategy in the doc is told to
# avoid), no entries before 09:30 (VWAP needs time to establish a slope after the open).
class VwapReversalStrategy < BaseStrategy
  IST = 'Asia/Kolkata'
  NO_TRADE_START = '11:00'
  NO_TRADE_END   = '13:30'
  SESSION_ENTRY_START = '09:30'

  def call(context)
    series = context.candles.call('3m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    rsi_period      = (params[:rsi_period] || 14).to_i
    rsi_low         = (params[:rsi_neutral_low] || 40).to_i
    rsi_high        = (params[:rsi_neutral_high] || 60).to_i
    band_pct        = (params[:vwap_touch_band_pct] || 0.10).to_f
    stop_buffer_pct = (params[:vwap_stop_buffer_pct] || 0.05).to_f
    min_rr          = (params[:min_reward_risk] || 1.5).to_f
    slope_lookback  = (params[:slope_lookback] || 6).to_i
    min_slope_pct   = (params[:min_slope_pct] || 0.05).to_f

    candles = series.candles
    current = candles.last
    now = current.timestamp.in_time_zone(IST)
    clock = now.strftime('%H:%M')

    return Signals::Hold.new(reason: 'pre_session_window') if clock < SESSION_ENTRY_START
    return Signals::Hold.new(reason: 'midday_dead_zone') if clock >= NO_TRADE_START && clock < NO_TRADE_END

    vwap_series = series.vwap
    return Signals::Hold.new(reason: 'vwap_unavailable') if vwap_series.blank? || vwap_series.size <= slope_lookback

    vwap = vwap_series.last
    return Signals::Hold.new(reason: 'vwap_unavailable') if vwap.nil? || vwap.zero?

    prior_vwap = vwap_series[-(slope_lookback + 1)]
    slope_pct = prior_vwap.positive? ? ((vwap - prior_vwap) / prior_vwap * 100.0) : 0.0
    return Signals::Hold.new(reason: 'flat_vwap') if slope_pct.abs < min_slope_pct

    rsi = series.rsi(rsi_period)
    return Signals::Hold.new(reason: 'rsi_unavailable') if rsi.nil?
    return Signals::Hold.new(reason: 'rsi_not_neutral') unless rsi.between?(rsi_low, rsi_high)

    today = now.to_date
    day_candles = candles.select { |c| c.timestamp.in_time_zone(IST).to_date == today }
    return Signals::Hold.new(reason: 'no_day_candles') if day_candles.size < 2

    prior_day_candles = day_candles[0...-1]
    prior_high = prior_day_candles.map(&:high).max
    prior_low  = prior_day_candles.map(&:low).min

    band = vwap * (band_pct / 100.0)
    stop_dist = vwap * (stop_buffer_pct / 100.0)

    if slope_pct.positive? && current.close > vwap
      call_signal = build_call_signal(current, vwap, band, stop_dist, prior_high, min_rr, rsi, slope_pct)
      return call_signal if call_signal
    elsif slope_pct.negative? && current.close < vwap
      put_signal = build_put_signal(current, vwap, band, stop_dist, prior_low, min_rr, rsi, slope_pct)
      return put_signal if put_signal
    end

    Signals::Hold.new(reason: 'no_reversal_setup')
  end

  private

  def build_call_signal(current, vwap, band, stop_dist, prior_high, min_rr, rsi, slope_pct)
    touched = current.low <= vwap + band
    confirming = current.close > vwap && current.close > current.open
    return nil unless touched && confirming

    stop = vwap - stop_dist
    risk = current.close - stop
    return nil if risk <= 0

    target = [prior_high, current.close + (min_rr * risk)].max
    Signals::BuyCall.new(
      confidence: 0.6,
      reason: "vwap_pullback_rsi_neutral rsi=#{rsi.round(1)} slope=#{slope_pct.round(2)}%",
      metadata: { exit_rules: { stop_index_level: stop, target_index_level: target, giveback_enabled: false } }
    )
  end

  def build_put_signal(current, vwap, band, stop_dist, prior_low, min_rr, rsi, slope_pct)
    touched = current.high >= vwap - band
    confirming = current.close < vwap && current.close < current.open
    return nil unless touched && confirming

    stop = vwap + stop_dist
    risk = stop - current.close
    return nil if risk <= 0

    target = [prior_low, current.close - (min_rr * risk)].min
    Signals::BuyPut.new(
      confidence: 0.6,
      reason: "vwap_rally_rsi_neutral rsi=#{rsi.round(1)} slope=#{slope_pct.round(2)}%",
      metadata: { exit_rules: { stop_index_level: stop, target_index_level: target, giveback_enabled: false } }
    )
  end
end
