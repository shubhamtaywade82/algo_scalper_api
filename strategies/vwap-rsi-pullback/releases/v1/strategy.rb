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
      rsi_period: { type: :integer, default: 14 },
      rsi_pullback_zone_low: { type: :float, default: 40.0 },
      rsi_pullback_zone_high: { type: :float, default: 60.0 },
      vwap_band_pct: { type: :float, default: 0.1 },
      min_slope_per_bar: { type: :float, default: 0.002 },
      dead_zone_start_hour: { type: :integer, default: 11 },
      dead_zone_end_hour: { type: :integer, default: 13 }
    }
  end

  def call(context)
    series = context.candles.call('3m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    candles = series.candles
    now = candles.last.timestamp.in_time_zone('Asia/Kolkata')

    # Need at least 15 min of data to establish VWAP
    warmup_end = Time.zone.parse("#{now.to_date} 09:30:00")
    if now < warmup_end
      return Signals::Hold.new(reason: 'warming_up_vwap')
    end

    return Signals::Hold.new(reason: 'insufficient_data') if candles.size < WARMUP_BARS

    # Dead zone filter
    dz_start = (params[:dead_zone_start_hour] || DEAD_ZONE_START).to_i
    dz_end   = (params[:dead_zone_end_hour] || DEAD_ZONE_END).to_i
    if now.hour >= dz_start && now.hour < dz_end
      return Signals::Hold.new(reason: 'midday_dead_zone')
    end

    # No entries at/after 2:30 PM (theta bleed). Must block ALL times >= 14:30:
    # `hour > 14 || (hour == 14 && min >= 30)`. The previous `hour >= 14 &&
    # now.min >= 30` form only blocked 14:30-14:59 and 15:30+ — a 15:05 candle
    # (hour=15>=14 true, min=05>=30 false) failed the AND and slipped through,
    # exactly the final-half-hour theta window this gate targets.
    if now.hour > 14 || (now.hour == 14 && now.min >= 30)
      return Signals::Hold.new(reason: 'late_entry_theta_risk')
    end

    # vwap_or_twap: DhanHQ index candles carry volume=0, so strict VWAP is nil
    # forever on index data — use the TWAP-fallback variant (see CandleSeries).
    vwap_values = series.vwap_or_twap
    return Signals::Hold.new(reason: 'vwap_unavailable') if vwap_values.blank? || vwap_values.size < 5

    current_vwap = vwap_values.last
    return Signals::Hold.new(reason: 'vwap_zero') if current_vwap.nil? || current_vwap.zero?

    close = candles.last.close
    distance_pct = ((close - current_vwap) / current_vwap) * 100.0

    # VWAP slope check, normalized as PERCENT of the VWAP level per bar (the same
    # price-normalized approach the vwap-reversal sibling uses) so min_slope_per_bar
    # is instrument-agnostic: 0.002 means "VWAP must rise/fall >= 0.002% per bar"
    # (~0.5 pts/bar on a 25,000 index). compute_vwap_slope used to return RAW
    # points per bar, so on NIFTY/SENSEX-scale prices virtually any slope cleared
    # the 0.002 threshold and the flat-VWAP gate never tripped.
    slope = compute_vwap_slope(vwap_values)
    min_slope = (params[:min_slope_per_bar] || 0.002).to_f # in % of VWAP level per bar
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
    rsi_in_zone = rsi_val.between?(zone_low, zone_high)

    band_pct = (params[:vwap_band_pct] || 0.1).to_f
    near_vwap = distance_pct.abs <= band_pct

    # UPTREND: price above VWAP, VWAP sloping up, pullback to VWAP zone
    if vwap_sloping_up && close > current_vwap && near_vwap && rsi_in_zone
      # Confirming candle: last candle closed higher than previous (bullish rejection)
      confirming = candles.size >= 2 && candles.last.close > candles[-2].close
      confidence = confirming ? 0.70 : 0.60
      confidence += 0.05 if slope > min_slope * 2 # strong slope bonus

      return Signals::BuyCall.new(
        confidence: confidence.clamp(0.5, 0.90).round(2),
        reason: "vwap_ce_pullback rsi=#{rsi_val.round(1)} dist=#{distance_pct.round(2)}% slope=#{slope.round(4)}%/bar"
      )
    end

    # DOWNTREND: price below VWAP, VWAP sloping down, rally to VWAP zone
    if vwap_sloping_down && close < current_vwap && near_vwap && rsi_in_zone
      # Confirming candle: last candle closed lower than previous (bearish rejection)
      confirming = candles.size >= 2 && candles.last.close < candles[-2].close
      confidence = confirming ? 0.70 : 0.60
      confidence += 0.05 if slope < -min_slope * 2 # strong slope bonus

      return Signals::BuyPut.new(
        confidence: confidence.clamp(0.5, 0.90).round(2),
        reason: "vwap_pe_rally rsi=#{rsi_val.round(1)} dist=#{distance_pct.round(2)}% slope=#{slope.round(4)}%/bar"
      )
    end

    Signals::Hold.new(reason: 'no_pullback_setup')
  end

  private

  # VWAP slope: linear regression of the last 5 VWAP values, normalized as a
  # percentage of the current VWAP level per bar (0.01 == +0.01%/bar) so the
  # min_slope_per_bar threshold means the same thing on NIFTY, BANKNIFTY and
  # SENSEX alike. Positive = VWAP rising (uptrend), negative = falling.
  def compute_vwap_slope(vwap_values, lookback: 5)
    return 0.0 if vwap_values.size < 3

    recent = vwap_values.last([lookback, vwap_values.size].min)
    n = recent.size
    return 0.0 if n < 2

    # Simple linear slope: (last - first) / (n - 1), in raw points per bar
    raw_slope = (recent.last - recent.first).to_f / (n - 1)
    level = recent.last.to_f
    return 0.0 unless level.positive?

    # Normalize to % of VWAP level per bar
    (raw_slope / level) * 100.0
  end
end
