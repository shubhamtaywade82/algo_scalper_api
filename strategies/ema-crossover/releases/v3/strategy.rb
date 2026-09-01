# frozen_string_literal: true

# EMA Crossover — doc-compliant implementation.
#
# Rules (from "Intraday Options Buying Strategies for Indian Index Derivatives"):
# - EMA 9/26 crossover on index chart (5-min), execute in ATM CE (bullish) / ATM PE (bearish).
# - One entry/exit per day.
# - Trading window: 9:15 – 15:20 IST.
# - Doc'd performance: ~35% win rate, 727 trades, 18-day losing streak,
#   but average gain far exceeds average loss (asymmetric payoff).
# - No entries during 11:00 AM – 1:00 PM dead zone.
# - ADX filter: only take crossover signals when ADX > threshold (trending market).
# - The SAHI variant (9/21 on 3-min) claims higher win rates, but is marketing
#   without published trade logs; we stick with the documented 9/26 on 5-min.
#
# Exit is handled by the parent backtester's exit simulation.
# This strategy only decides entry timing and direction.

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

class EmaCrossoverStrategy < BaseStrategy
  WARMUP_BARS = 30
  DEAD_ZONE_START = 11
  DEAD_ZONE_END   = 13

  def self.timeframes = %w[5m]
  def self.instruments = %w[NIFTY BANKNIFTY SENSEX]

  def self.params_schema
    {
      fast_ema_period: { type: :integer, default: 9 },
      slow_ema_period: { type: :integer, default: 26 },
      min_separation_pct: { type: :float, default: 0.02 },
      adx_threshold: { type: :float, default: 20.0 },
      dead_zone_start_hour: { type: :integer, default: 11 },
      dead_zone_end_hour: { type: :integer, default: 13 }
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

    # No entries after 3:15 PM
    if now.hour >= 15 && now.min >= 15
      return Signals::Hold.new(reason: 'late_entry')
    end

    fast_period = (params[:fast_ema_period] || 9).to_i
    slow_period = (params[:slow_ema_period] || 26).to_i

    # Compute EMAs using the RubyTechnicalAnalysis gem via CandleSeries
    fast_ema = series.ema(fast_period)
    slow_ema = series.ema(slow_period)
    return Signals::Hold.new(reason: 'ema_unavailable') if fast_ema.nil? || slow_ema.nil?

    # EMAs are arrays aligned with candles — we need the last two values
    # to detect a crossover.
    fast_arr = Array(fast_ema)
    slow_arr = Array(slow_ema)
    return Signals::Hold.new(reason: 'ema_arrays_too_short') if fast_arr.size < 2 || slow_arr.size < 2

    prev_fast = fast_arr[-2]
    curr_fast = fast_arr[-1]
    prev_slow = slow_arr[-2]
    curr_slow = slow_arr[-1]

    # Guard against nil EMA values (gem may pad leading values with nil)
    return Signals::Hold.new(reason: 'ema_values_nil') if [prev_fast, curr_fast, prev_slow, curr_slow].any?(&:nil?)

    # Detect crossover on the CURRENT bar (just happened)
    bullish_crossover = prev_fast <= prev_slow && curr_fast > curr_slow
    bearish_crossover = prev_fast >= prev_slow && curr_fast < curr_slow

    unless bullish_crossover || bearish_crossover
      return Signals::Hold.new(reason: 'no_crossover')
    end

    # ADX trend-strength filter (doc: EMA crossover needs trending market)
    adx_threshold = (params[:adx_threshold] || 20.0).to_f
    adx_val = series.adx(14)
    if adx_val && adx_val < adx_threshold
      return Signals::Hold.new(reason: "weak_trend_adx=#{adx_val.round(1)}")
    end

    # Separation filter: EMAs should be meaningfully separated after crossover
    close = candles.last.close
    min_sep = (params[:min_separation_pct] || 0.02).to_f
    separation_pct = ((curr_fast - curr_slow).abs / close * 100.0)
    if separation_pct < min_sep
      return Signals::Hold.new(reason: "insufficient_separation_#{separation_pct.round(3)}%")
    end

    if bullish_crossover
      confidence = 0.55
      confidence += 0.10 if adx_val && adx_val > 30
      confidence += 0.05 if separation_pct > min_sep * 2
      confidence = confidence.clamp(0.5, 0.85).round(2)

      Signals::BuyCall.new(
        confidence: confidence,
        reason: "ema_bullish_xover fast=#{curr_fast.round(2)} slow=#{curr_slow.round(2)} adx=#{adx_val&.round(1)}"
      )
    else
      confidence = 0.55
      confidence += 0.10 if adx_val && adx_val > 30
      confidence += 0.05 if separation_pct > min_sep * 2
      confidence = confidence.clamp(0.5, 0.85).round(2)

      Signals::BuyPut.new(
        confidence: confidence,
        reason: "ema_bearish_xover fast=#{curr_fast.round(2)} slow=#{curr_slow.round(2)} adx=#{adx_val&.round(1)}"
      )
    end
  end
end
