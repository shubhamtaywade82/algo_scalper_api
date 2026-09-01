# frozen_string_literal: true

# VWAP + RSI Pullback — doc-compliant implementation.
#
# Rules (from "Intraday Options Buying Strategies for Indian Index Derivatives"):
# - Wait for first 15-30 min to establish VWAP slope.
# - Uptrend (price above VWAP, VWAP clearly sloping up): buy CE on pullbacks to VWAP.
# - Downtrend (price below VWAP, VWAP clearly sloping down): buy PE on rallies to VWAP.
# - RSI in the 40-60 zone (healthy pullback, not overbought/oversold).
# - Require a confirming candle (close back toward VWAP after touching it).
# - Only trade when VWAP is clearly sloping — flat VWAP = no trade.
# - Hard no-trade block 11:00 AM – 1:00 PM IST (midday dead zone).
# - Target prior intraday swing high/low, minimum 1.5:1 R:R.
# - SL just beyond VWAP (5-10 pts on Nifty).
# - ~60-70% of setups trigger in 9:30-11:00 AM window.
#
# Exit is handled by the parent backtester's exit simulation.
# This strategy only decides entry timing and direction.

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

class VwapRsiPullbackStrategy < BaseStrategy
  WARMUP_BARS = 10
  DEAD_ZONE_START = 11  # 11:00 AM IST
  DEAD_ZONE_END   = 13  # 1:00 PM IST

  def self.timeframes = %w[3m]
  def self.instruments = %w[NIFTY BANKNIFTY SENSEX]

  def self.params_schema
    {
      rsi_period:            { type: :integer, default: 14 },
      rsi_pullback_zone_low:  { type: :float,   default: 40.0 },
      rsi_pullback_zone_high: { type: :float,   default: 60.0 },
      vwap_band_pct:         { type: :float,   default: 0.1 },
      min_slope_per_bar:     { type: :float,   default: 0.002 },
      dead_zone_start_hour:  { type: :integer, default: 11 },
      dead_zone_end_hour:    { type: :integer, default: 13 }
    }
  end

  def call(context)
    series = context.candles.call('3m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    candles = series.candles
    return Signals::Hold.new(reason: 'insufficient_data') if candles.size < WARMUP_BARS

    now = candles.last.timestamp.in_time_zone('Asia/Kolkata')

    # Need at least 15 min of data to establish VWAP
    warmup_end = Time.zone.parse("#{now.to_date} 09:30:00")
    if now < warmup_end
      return Signals::Hold.new(reason: 'warming_up_vwap')
    end

    # Dead zone filter
    dz_start = (params[:dead_zone_start_hour] || DEAD_ZONE_START).to_i
    dz_end   = (params[:dead_zone_end_hour] || DEAD_ZONE_END).to_i
    if now.hour >= dz_start && now.hour < dz_end
      return Signals::Hold.new(reason: 'midday_dead_zone')
    end

    # No entries after 2:30 PM (theta bleed)
    if now.hour >= 14 && now.min >= 30
      return Signals::Hold.new(reason: 'late_entry_theta_risk')
    end

    vwap_values = series.vwap
    return Signals::Hold.new(reason: 'vwap_unavailable') if vwap_values.blank? || vwap_values.size < 5

    current_vwap = vwap_values.last
    return Signals::Hold.new(reason: 'vwap_zero') if current_vwap.nil? || current_vwap.zero?

    close = candles.last.close
    distance_pct = ((close - current_vwap) / current_vwap) * 100.0

    # VWAP slope check: compare VWAP from 5 bars ago to current
    slope = compute_vwap_slope(vwap_values)
    min_slope = (params[:min_slope_per_bar] || 0.002).to_f
    vwap_sloping_up   = slope > min_slope
    vwap_sloping_down = slope < -min_slope

    # Flat VWAP = no trade (doc: "Only trade when VWAP is clearly sloping")
    unless vwap_sloping_up || vwap_sloping_down
      return Signals::Hold.new(reason: 'flat_vwap_no_trend')
    end

    # RSI check
    rsi_period = (params[:rsi_period] || 14).to_i
    rsi_val = series.rsi(rsi_period)
    return Signals::Hold.new(reason: 'rsi_unavailable') if rsi_val.nil?

    zone_low  = (params[:rsi_pullback_zone_low] || 40.0).to_f
    zone_high = (params[:rsi_pullback_zone_high] || 60.0).to_f
    rsi_in_zone = rsi_val >= zone_low && rsi_val <= zone_high

    band_pct = (params[:vwap_band_pct] || 0.1).to_f
    near_vwap = distance_pct.abs <= band_pct

    # UPTREND: price above VWAP, VWAP sloping up, pullback to VWAP zone
    if vwap_sloping_up && close > current_vwap && near_vwap && rsi_in_zone
      # Confirming candle: last candle closed higher than previous (bullish rejection)
      confirming = candles.size >= 2 && candles.last.close > candles[-2].close
      confidence = confirming ? 0.70 : 0.60
      confidence += 0.05 if slope > min_slope * 2  # strong slope bonus

      return Signals::BuyCall.new(
        confidence: confidence.clamp(0.5, 0.90).round(2),
        reason: "vwap_ce_pullback rsi=#{rsi_val.round(1)} dist=#{distance_pct.round(2)}% slope=#{slope.round(4)}"
      )
    end

    # DOWNTREND: price below VWAP, VWAP sloping down, rally to VWAP zone
    if vwap_sloping_down && close < current_vwap && near_vwap && rsi_in_zone
      # Confirming candle: last candle closed lower than previous (bearish rejection)
      confirming = candles.size >= 2 && candles.last.close < candles[-2].close
      confidence = confirming ? 0.70 : 0.60
      confidence += 0.05 if slope < -min_slope * 2  # strong slope bonus

      return Signals::BuyPut.new(
        confidence: confidence.clamp(0.5, 0.90).round(2),
        reason: "vwap_pe_rally rsi=#{rsi_val.round(1)} dist=#{distance_pct.round(2)}% slope=#{slope.round(4)}"
      )
    end

    Signals::Hold.new(reason: 'no_pullback_setup')
  end

  private

  # VWAP slope: linear regression of last 5 VWAP values, returned as change per bar.
  # Positive = VWAP rising (uptrend), negative = VWAP falling (downtrend).
  def compute_vwap_slope(vwap_values, lookback: 5)
    return 0.0 if vwap_values.size < 3

    recent = vwap_values.last([lookback, vwap_values.size].min)
    n = recent.size
    return 0.0 if n < 2

    # Simple linear slope: (last - first) / (n - 1)
    (recent.last - recent.first).to_f / (n - 1)
  end
end
