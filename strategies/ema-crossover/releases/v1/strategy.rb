# frozen_string_literal: true

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

# EMA 9/26 crossover, per the doc's Strategy 3 (Marketcalls): buy ATM CE on a bullish 9/26
# crossover, ATM PE on a bearish one, one signal per day. The doc reports this setup's own
# backtest (35% win rate, average win >> average loss, no published SL/target rule) without
# a documented exit methodology, so the exit here follows the doc's Stage 3 universal risk
# architecture instead: an ATR-based underlying stop (1.5-2x ATR) rather than a fixed-%
# premium stop, with a 2:1 target off that same ATR distance.
class EmaCrossoverStrategy < BaseStrategy
  IST = 'Asia/Kolkata'

  def call(context)
    series = context.candles.call('5m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    fast = (params[:fast_period] || 9).to_i
    slow = (params[:slow_period] || 26).to_i
    atr_period = (params[:atr_period] || 14).to_i
    atr_mult = (params[:atr_multiplier] || 1.75).to_f
    r_multiple = (params[:target_r_multiple] || 2.0).to_f
    strike_pref = (params[:strike_pref] || 'ATM').to_s

    candles = series.candles
    return Signals::Hold.new(reason: 'insufficient_history') if candles.size <= slow

    current = candles.last
    now = current.timestamp.in_time_zone(IST)
    today = now.to_date

    day_candles = candles.select { |c| c.timestamp.in_time_zone(IST).to_date == today }
    return Signals::Hold.new(reason: 'no_day_candles') if day_candles.empty?
    return Signals::Hold.new(reason: 'already_traded_today') if already_crossed_today?(candles, day_candles, fast, slow)

    ema_fast_curr = series.ema(fast)
    ema_slow_curr = series.ema(slow)
    return Signals::Hold.new(reason: 'ema_unavailable') if ema_fast_curr.nil? || ema_slow_curr.nil?

    prev_series = sub_series_upto(candles, candles.size - 2)
    ema_fast_prev = prev_series.ema(fast)
    ema_slow_prev = prev_series.ema(slow)
    return Signals::Hold.new(reason: 'ema_unavailable') if ema_fast_prev.nil? || ema_slow_prev.nil?

    atr = series.atr(atr_period)
    return Signals::Hold.new(reason: 'atr_unavailable') if atr.nil? || atr <= 0

    stop_distance = atr * atr_mult
    bullish_cross = ema_fast_prev <= ema_slow_prev && ema_fast_curr > ema_slow_curr
    bearish_cross = ema_fast_prev >= ema_slow_prev && ema_fast_curr < ema_slow_curr

    if bullish_cross
      stop = current.close - stop_distance
      target = current.close + (r_multiple * stop_distance)
      return Signals::BuyCall.new(
        confidence: 0.55,
        reason: "ema_crossover_up #{fast}/#{slow} atr=#{atr.round(1)}",
        metadata: { strike_pref: strike_pref, exit_rules: { stop_index_level: stop, target_index_level: target, giveback_enabled: false } }
      )
    elsif bearish_cross
      stop = current.close + stop_distance
      target = current.close - (r_multiple * stop_distance)
      return Signals::BuyPut.new(
        confidence: 0.55,
        reason: "ema_crossover_down #{fast}/#{slow} atr=#{atr.round(1)}",
        metadata: { strike_pref: strike_pref, exit_rules: { stop_index_level: stop, target_index_level: target, giveback_enabled: false } }
      )
    end

    Signals::Hold.new(reason: 'no_crossover')
  end

  private

  # CandleSeries#ema(period) only exposes the latest value (no full series), so a crossover
  # check needs two truncated series — one ending at the current bar, one ending at the prior
  # bar — to compare the fast/slow relationship across a single step.
  def sub_series_upto(all_candles, upto_index)
    sub = CandleSeries.new(symbol: 'ema_crossover_scan', interval: '5')
    all_candles.first(upto_index + 1).each { |c| sub.add_candle(c) }
    sub
  end

  # One trade/day: suppress a new signal if the fast/slow relationship already flipped at any
  # earlier candle today (i.e. a crossover already fired today), regardless of what today's
  # first candle happened to be relative to slow.
  def already_crossed_today?(all_candles, day_candles, fast, slow)
    first_ts = day_candles.first.timestamp
    start_idx = all_candles.index { |c| c.timestamp == first_ts }
    return false if start_idx.nil?

    end_idx = all_candles.size - 2 # exclude the current (last) candle
    scan_start = [start_idx, slow].max
    return false if end_idx < scan_start

    # NOTE: deliberately not filter_map — it drops `false` results along with `nil`, which
    # would silently discard every "not yet crossed" reading and leave only `true`s behind.
    relations = []
    (scan_start..end_idx).each do |i|
      s = sub_series_upto(all_candles, i)
      f = s.ema(fast)
      sl = s.ema(slow)
      next if f.nil? || sl.nil?

      relations << (f > sl)
    end

    relations.uniq.size > 1
  end
end
