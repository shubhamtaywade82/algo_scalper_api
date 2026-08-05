# frozen_string_literal: true

# Extracts historical ATM options behaviour analysis from the rake task
# into a reusable service for API consumption.
#
# Usage:
#   analyzer = HistoricalOptionsAnalyzer.new('NIFTY', weeks: 8)
#   result   = analyzer.analyze
#   # => { symbol: 'NIFTY', ce_aggregate: {...}, pe_aggregate: {...}, cycles: [...], calibration: {...} }
class HistoricalOptionsAnalyzer
  SESSIONS = {
    'Morning' => ((9 * 60) + 15)..(11 * 60),
    'Midday' => ((11 * 60) + 1)..(13 * 60),
    'Afternoon' => ((13 * 60) + 1)..((15 * 60) + 30)
  }.freeze

  DOW = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  CACHE_TTL = 1.hour
  REQUIRED_OHLCV_FIELDS = %w[open high low close volume oi spot strike].freeze

  def initialize(symbol, weeks: 8, interval: '5')
    @symbol   = symbol.upcase
    @weeks    = weeks
    @interval = interval
  end

  def analyze
    cache_key = "historical_options:#{@symbol}:#{@weeks}:#{@interval}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    result = compute_analysis
    Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
    result
  end

  private

  def compute_analysis
    instrument = Instrument.where(segment: 'I', symbol_name: @symbol).first
    return { error: "Instrument not found for #{@symbol}" } unless instrument

    security_id = instrument.security_id
    segment = @symbol == 'SENSEX' ? 'BSE_FNO' : 'NSE_FNO'

    windows = expiry_windows(@weeks)
    all_ce_stats = []
    all_pe_stats = []
    cycles = []

    windows.each do |w|
      from_str = w[:from].strftime('%Y-%m-%d')
      to_str   = w[:to].strftime('%Y-%m-%d')

      ce_raw = fetch_options(security_id, segment, from_str, to_str, 'CALL')
      pe_raw = fetch_options(security_id, segment, from_str, to_str, 'PUT')

      ce_stat = cycle_stats(ce_raw)
      pe_stat = cycle_stats(pe_raw)
      ce_sess = session_breakdown(ce_raw)
      pe_sess = session_breakdown(pe_raw)
      ce_days = day_breakdown(ce_raw)
      pe_days = day_breakdown(pe_raw)
      ce_corr = spot_option_correlation(ce_raw)
      pe_corr = spot_option_correlation(pe_raw)

      all_ce_stats << ce_stat
      all_pe_stats << pe_stat

      cycles << {
        expiry: w[:expiry].strftime('%Y-%m-%d'),
        from: from_str,
        to: to_str,
        ce: ce_stat,
        pe: pe_stat,
        ce_sessions: ce_sess,
        pe_sessions: pe_sess,
        ce_days: ce_days,
        pe_days: pe_days,
        ce_correlation: ce_corr,
        pe_correlation: pe_corr
      }

      sleep 0.25 # Rate limit
    end

    ce_agg = aggregate_summary(all_ce_stats)
    pe_agg = aggregate_summary(all_pe_stats)

    {
      symbol: @symbol,
      weeks: @weeks,
      interval: @interval,
      generated_at: Time.current.iso8601,
      ce_aggregate: ce_agg,
      pe_aggregate: pe_agg,
      cycles: cycles,
      calibration: build_calibration(ce_agg, pe_agg)
    }
  end

  def last_thursday(date)
    date - ((date.wday - 4) % 7).days
  end

  def expiry_windows(weeks)
    today = Time.zone.today
    current_expiry = last_thursday(today)
    windows = Array.new(weeks) do |i|
      expiry = current_expiry - (i * 7).days
      { expiry: expiry, from: expiry - 6.days, to: expiry }
    end
    windows.reverse
  end

  def pct(v, b)
    b.zero? ? 0.0 : ((v - b) / b.to_f * 100).round(2)
  end

  def fetch_options(security_id, segment, from_str, to_str, opt_type)
    raw = DhanHQ::Models::ExpiredOptionsData.fetch(
      exchange_segment: segment,
      interval: @interval,
      security_id: security_id,
      instrument: 'OPTIDX',
      expiry_flag: 'WEEK',
      expiry_code: 1,
      strike: 'ATM',
      drv_option_type: opt_type,
      required_data: %w[open high low close volume oi spot strike],
      from_date: from_str,
      to_date: to_str
    )
    side = opt_type == 'CALL' ? 'ce' : 'pe'
    d = raw&.data&.[](side)
    return [] unless d && d['timestamp']

    d['timestamp'].map.with_index do |ts, i|
      t = Time.at(ts).in_time_zone('Asia/Kolkata')
      {
        time: t.iso8601,
        day: t.wday,
        day_str: DOW[t.wday],
        mins: (t.hour * 60) + t.min,
        open: d['open'][i].to_f,
        high: d['high'][i].to_f,
        low: d['low'][i].to_f,
        close: d['close'][i].to_f,
        volume: d['volume'][i].to_i,
        oi: d['oi'][i].to_i,
        spot: d['spot'][i].to_f,
        strike: d['strike'][i].to_f
      }
    end
  rescue StandardError => e
    Rails.logger.warn("[HistoricalOptionsAnalyzer] #{@symbol} #{opt_type}: #{e.message}")
    []
  end

  def cycle_stats(candles)
    return nil if candles.empty?

    entry   = candles.first[:open].to_f
    max_h   = candles.pluck(:high).max.to_f
    min_l   = candles.pluck(:low).min.to_f
    final_c = candles.last[:close].to_f
    vols    = candles.pluck(:volume)
    ois     = candles.pluck(:oi)
    spots   = candles.pluck(:spot)

    peak_idx   = candles.index { |c| c[:high] == max_h }
    post_peak  = candles[(peak_idx || 0)..]
    pullback_l = post_peak.pluck(:low).min.to_f

    {
      entry: entry.round(2),
      max_high: max_h.round(2),
      max_low: min_l.round(2),
      exit: final_c.round(2),
      max_gain_pct: pct(max_h, entry),
      max_loss_pct: pct(min_l, entry),
      open_to_close_pct: pct(final_c, entry),
      post_peak_retrace: pct(pullback_l, max_h).round(2),
      avg_volume: (vols.compact.sum / [vols.size, 1].max).round(0),
      oi_open: ois.first.to_i,
      oi_close: ois.last.to_i,
      oi_change_pct: pct(ois.last.to_f, ois.first.to_f),
      spot_open: spots.first.to_f.round(2),
      spot_close: spots.last.to_f.round(2),
      spot_change_pct: pct(spots.last.to_f, spots.first.to_f),
      strike: candles.first[:strike].to_f.round(0),
      candle_count: candles.size
    }
  end

  def day_breakdown(candles)
    candles.group_by { |c| c[:day_str] }.transform_values do |day_candles|
      day_open  = day_candles.first[:open].to_f
      day_close = day_candles.last[:close].to_f
      day_high  = day_candles.map { |c| c[:high] }.max.to_f
      day_low   = day_candles.map { |c| c[:low] }.min.to_f
      {
        open: day_open.round(2),
        high: day_high.round(2),
        low: day_low.round(2),
        close: day_close.round(2),
        high_pct: pct(day_high, day_open),
        low_pct: pct(day_low, day_open),
        oc_pct: pct(day_close, day_open),
        candles: day_candles.size
      }
    end
  end

  def session_breakdown(candles)
    SESSIONS.transform_values do |range|
      sess = candles.select { |c| range.cover?(c[:mins]) }
      next nil if sess.empty?

      s_open  = sess.first[:open].to_f
      s_close = sess.last[:close].to_f
      s_high  = sess.map { |c| c[:high] }.max.to_f
      s_low   = sess.map { |c| c[:low] }.min.to_f
      {
        open: s_open.round(2),
        high: s_high.round(2),
        low: s_low.round(2),
        close: s_close.round(2),
        high_pct: pct(s_high, s_open),
        low_pct: pct(s_low, s_open),
        oc_pct: pct(s_close, s_open),
        candles: sess.size
      }
    end
  end

  def spot_option_correlation(candles)
    return nil if candles.empty?

    base_spot   = candles.first[:spot].to_f
    base_option = candles.first[:open].to_f
    return nil if base_spot.zero? || base_option.zero?

    pairs = candles.map do |c|
      spot_chg   = pct(c[:spot].to_f, base_spot)
      option_chg = pct(c[:close].to_f, base_option)
      [spot_chg, option_chg]
    end

    n   = pairs.size.to_f
    sx  = pairs.sum { |x, _| x }
    sy  = pairs.sum { |_, y| y }
    sx2 = pairs.sum { |x, _| x**2 }
    sxy = pairs.sum { |x, y| x * y }
    denom = ((n * sx2) - (sx**2))
    return nil if denom.zero?

    slope = (((n * sxy) - (sx * sy)) / denom).round(2)
    { slope: slope, note: "Option moves ~#{slope}x per 1% spot move" }
  end

  def aggregate_summary(all_stats)
    valid = all_stats.compact
    return nil if valid.empty?

    keys = %i[max_gain_pct max_loss_pct open_to_close_pct post_peak_retrace oi_change_pct spot_change_pct]
    avg = keys.index_with { |k| (valid.sum { |s| s[k].to_f } / valid.size).round(2) }
    max = keys.index_with { |k| valid.map { |s| s[k].to_f }.max.round(2) }
    min = keys.index_with { |k| valid.map { |s| s[k].to_f }.min.round(2) }

    { avg: avg, max: max, min: min, n: valid.size }
  end

  def build_calibration(ce_agg, pe_agg)
    calibration = {}

    if ce_agg
      avg_gain    = ce_agg[:avg][:max_gain_pct]
      avg_retrace = ce_agg[:avg][:post_peak_retrace].abs
      calibration[:ce] = {
        avg_max_gain_pct: avg_gain,
        avg_retrace_pct: avg_retrace,
        suggested_trail_pct: (avg_retrace * 0.8).round(1),
        breakeven_trigger_pct: (avg_gain * 0.25).round(1)
      }
    end

    if pe_agg
      avg_gain    = pe_agg[:avg][:max_gain_pct]
      avg_retrace = pe_agg[:avg][:post_peak_retrace].abs
      calibration[:pe] = {
        avg_max_gain_pct: avg_gain,
        avg_retrace_pct: avg_retrace,
        suggested_trail_pct: (avg_retrace * 0.8).round(1),
        breakeven_trigger_pct: (avg_gain * 0.25).round(1)
      }
    end

    calibration
  end
end
