# frozen_string_literal: true

# Supertrend + VWAP — doc-compliant implementation.
#
# Rules (from "Intraday Options Buying Strategies for Indian Index Derivatives"):
# - Supertrend(10,3) on 5-min index chart.
# - Buy CE only when: Supertrend is green (bullish) AND price above VWAP.
# - Buy PE only when: Supertrend is red (bearish) AND price below VWAP.
# - Doc notes Supertrend raw hit rate is only ~40-45%; no credible options-buying
#   backtest exists. Treat as a trend filter, not a standalone edge.
# - SL at the Supertrend line; target previous swing high/low.
# - No entries during 11:00 AM – 1:00 PM dead zone.
# - Skip when VWAP is flat (no clear trend).
#
# Exit is handled by the parent backtester's exit simulation.
# This strategy only decides entry timing and direction.

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

class SupertrendVwapStrategy < BaseStrategy
  WARMUP_BARS = 20
  DEAD_ZONE_START = 11
  DEAD_ZONE_END   = 13

  def self.timeframes = %w[5m]
  def self.instruments = %w[NIFTY BANKNIFTY SENSEX]

  def self.params_schema
    {
      supertrend_period:     { type: :integer, default: 10 },
      supertrend_multiplier: { type: :float,   default: 3.0 },
      dead_zone_start_hour:  { type: :integer, default: 11 },
      dead_zone_end_hour:    { type: :integer, default: 13 }
    }
  end

  def call(context)
    series = context.candles.call('5m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    candles = series.candles
    return Signals::Hold.new(reason: 'insufficient_data') if candles.size < WARMUP_BARS

    now = candles.last.timestamp.in_time_zone('Asia/Kolkata')

    # Dead zone filter
    dz_start = (params[:dead_zone_start_hour] || DEAD_ZONE_START).to_i
    dz_end   = (params[:dead_zone_end_hour] || DEAD_ZONE_END).to_i
    if now.hour >= dz_start && now.hour < dz_end
      return Signals::Hold.new(reason: 'midday_dead_zone')
    end

    # No entries after 2:30 PM
    if now.hour >= 14 && now.min >= 30
      return Signals::Hold.new(reason: 'late_entry_theta_risk')
    end

    # VWAP check
    vwap_values = series.vwap
    return Signals::Hold.new(reason: 'vwap_unavailable') if vwap_values.blank? || vwap_values.size < 5

    current_vwap = vwap_values.last
    return Signals::Hold.new(reason: 'vwap_zero') if current_vwap.nil? || current_vwap.zero?

    close = candles.last.close
    above_vwap = close > current_vwap
    below_vwap = close < current_vwap

    # VWAP slope check — flat VWAP = no trade
    slope = compute_vwap_slope(vwap_values)
    min_slope = 0.002
    unless slope.abs > min_slope
      return Signals::Hold.new(reason: 'flat_vwap_no_trend')
    end

    # Supertrend signal
    st_period = (params[:supertrend_period] || 10).to_i
    st_mult   = (params[:supertrend_multiplier] || 3.0).to_f
    st_signal = series.supertrend_signal(period: st_period, multiplier: st_mult)
    return Signals::Hold.new(reason: 'supertrend_warming_up') if st_signal.nil?

    st_bullish = st_signal == :long_entry
    st_bearish = st_signal == :short_entry

    # CE: Supertrend bullish AND price above VWAP AND VWAP sloping up
    if st_bullish && above_vwap && slope > 0
      confidence = 0.55
      confidence += 0.10 if slope > min_slope * 3
      confidence += 0.05 if (close - current_vwap).abs / current_vwap > 0.003
      confidence = confidence.clamp(0.50, 0.85).round(2)

      return Signals::BuyCall.new(
        confidence: confidence,
        reason: "st_vwap_ce st=:bullish above_vwap dist=#{((close - current_vwap) / current_vwap * 100).round(3)}% slope=#{slope.round(4)}"
      )
    end

    # PE: Supertrend bearish AND price below VWAP AND VWAP sloping down
    if st_bearish && below_vwap && slope < 0
      confidence = 0.55
      confidence += 0.10 if slope < -min_slope * 3
      confidence += 0.05 if (current_vwap - close).abs / current_vwap > 0.003
      confidence = confidence.clamp(0.50, 0.85).round(2)

      return Signals::BuyPut.new(
        confidence: confidence,
        reason: "st_vwap_pe st=:bearish below_vwap dist=#{((current_vwap - close) / current_vwap * 100).round(3)}% slope=#{slope.round(4)}"
      )
    end

    Signals::Hold.new(reason: 'no_aligned_setup')
  end

  private

  def compute_vwap_slope(vwap_values, lookback: 5)
    return 0.0 if vwap_values.size < 3

    recent = vwap_values.last([lookback, vwap_values.size].min)
    n = recent.size
    return 0.0 if n < 2

    (recent.last - recent.first).to_f / (n - 1)
  end
end
