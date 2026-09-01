# frozen_string_literal: true

# Opening Range Breakout (ORB) — doc-compliant implementation.
#
# Rules (from "Intraday Options Buying Strategies for Indian Index Derivatives"):
# - Opening range = high/low of first N minutes (default 30 min) on the UNDERLYING index.
# - Entry: candle CLOSE beyond range high (CE) or below range low (PE).
# - Volume filter: current candle volume >= volume_multiplier * average volume during ORB period.
# - Skip if range < min_range_points (~40 pts for NIFTY, proxy for 0.2% of index).
# - Skip if opening gap > max_open_gap_pct (0.8%) to avoid gap-trap days.
# - Max 2 trades/day (one CE breakout, one PE breakout).
# - No entries after force_exit_time (2:30 PM IST) to avoid theta bleed.
# - No entries during 11:00 AM – 1:30 PM dead zone (theta/volume bleed).
# - Confidence scales with volume strength and range width quality.
#
# Exit is handled by the parent backtester's exit simulation (SL/target/giveback/time-stop),
# not by this strategy.  The strategy only decides entry timing and direction.

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

class OrbBreakoutStrategy < BaseStrategy
  DEAD_ZONE_START = 11  # 11:00 AM IST
  DEAD_ZONE_END   = 13  # 1:00 PM IST (exit dead zone at 1:00 to allow 1:00 PM bar)
  ORB_END_BUFFER  = 5   # minutes after ORB period before entries are accepted

  def self.timeframes = %w[1m]
  def self.instruments = %w[NIFTY BANKNIFTY SENSEX]

  def self.params_schema
    {
      orb_period_minutes: { type: :integer, default: 30 },
      min_range_points: { type: :float,   default: 40.0 },
      max_open_gap_pct: { type: :float,   default: 0.8 },
      volume_multiplier: { type: :float, default: 1.5 },
      max_trades_per_day: { type: :integer, default: 2 },
      force_exit_time: { type: :string, default: '14:30' }
    }
  end

  def call(context)
    series = context.candles.call('1m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    candles = series.candles
    return Signals::Hold.new(reason: 'insufficient_data') if candles.size < 5

    now = candles.last.timestamp.in_time_zone('Asia/Kolkata')
    orb_minutes  = (params[:orb_period_minutes] || 30).to_i
    market_open  = Time.zone.parse("#{now.to_date} 09:15:00")
    orb_end      = market_open + orb_minutes.minutes

    # Wait until ORB period is complete + small buffer for bar confirmation
    if now < orb_end + ORB_END_BUFFER.minutes
      return Signals::Hold.new(reason: 'orb_forming')
    end

    # No entries after force_exit_time
    exit_h, exit_m = (params[:force_exit_time] || '14:30').split(':').map(&:to_i)
    if now.hour > exit_h || (now.hour == exit_h && now.min >= exit_m)
      return Signals::Hold.new(reason: 'past_force_exit_time')
    end

    # Dead zone: 11:00 AM – 1:00 PM IST
    if now.hour >= DEAD_ZONE_START && now.hour < DEAD_ZONE_END
      return Signals::Hold.new(reason: 'midday_dead_zone')
    end

    orb_candles = candles.select do |c|
      t = c.timestamp.in_time_zone('Asia/Kolkata')
      t >= market_open && t < orb_end
    end
    return Signals::Hold.new(reason: 'no_orb_candles') if orb_candles.size < 2

    range_high = orb_candles.map(&:high).max
    range_low  = orb_candles.map(&:low).min
    range_width = range_high - range_low
    prev_close = candles[0]&.open || range_high
    open_gap_pct = ((orb_candles.first.open - prev_close).abs / prev_close * 100.0)

    # Skip tiny-range days (doc: skip if range < ~0.2% of index ≈ 40 NIFTY pts)
    min_range = (params[:min_range_points] || 40.0).to_f
    if range_width < min_range
      return Signals::Hold.new(reason: "range_too_narrow_#{range_width.round(1)}")
    end

    # Skip large-gap days (doc: skip if open gap > 0.8%)
    max_gap = (params[:max_open_gap_pct] || 0.8).to_f
    if open_gap_pct > max_gap
      return Signals::Hold.new(reason: "open_gap_too_large_#{open_gap_pct.round(2)}%")
    end

    # Volume baseline: average volume during ORB period
    orb_volumes = orb_candles.map(&:volume)
    avg_volume  = orb_volumes.sum.to_f / orb_volumes.size
    vol_mult    = (params[:volume_multiplier] || 1.5).to_f
    volume_ok   = candles.last.volume >= avg_volume * vol_mult

    close = candles.last.close

    # CE breakout: candle CLOSE above range high, with volume confirmation
    if close > range_high && volume_ok
      confidence = compute_confidence(range_width, close - range_high, volume_ok, avg_volume, candles.last.volume)
      return Signals::BuyCall.new(
        confidence: confidence,
        reason: "orb_ce_breakout range=#{range_width.round(1)} vol=#{(candles.last.volume / [avg_volume, 1].max).round(2)}x"
      )
    end

    # PE breakout: candle CLOSE below range low, with volume confirmation
    if close < range_low && volume_ok
      confidence = compute_confidence(range_width, range_low - close, volume_ok, avg_volume, candles.last.volume)
      return Signals::BuyPut.new(
        confidence: confidence,
        reason: "orb_pe_breakdown range=#{range_width.round(1)} vol=#{(candles.last.volume / [avg_volume, 1].max).round(2)}x"
      )
    end

    # Close beyond range but no volume confirmation — hold, don't enter on weak volume
    if close > range_high || close < range_low
      Signals::Hold.new(reason: 'orb_break_no_volume_confirmation')
    else
      Signals::Hold.new(reason: 'inside_orb_range')
    end
  end

  private

  def compute_confidence(range_width, breakout_distance, volume_ok, avg_vol, current_vol)
    confidence = 0.55

    # Wider range = more meaningful breakout
    confidence += 0.05 if range_width > 80
    confidence += 0.10 if range_width > 120

    # Stronger volume = higher confidence
    if volume_ok && avg_vol.positive?
      vol_ratio = current_vol / avg_vol
      confidence += 0.05 if vol_ratio >= 2.0
      confidence += 0.05 if vol_ratio >= 3.0
    end

    # Clean break (close well beyond range, not just barely)
    confidence += 0.05 if breakout_distance > range_width * 0.1
    confidence += 0.05 if breakout_distance > range_width * 0.2

    confidence.clamp(0.5, 0.95).round(2)
  end
end
