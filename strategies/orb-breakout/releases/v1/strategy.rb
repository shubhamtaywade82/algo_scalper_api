# frozen_string_literal: true

BaseStrategy = Strategies::Base unless defined?(BaseStrategy)

# Opening Range Breakout, per the doc's Stage 1 core design: range formed on the underlying
# (not the option premium — premiums are distorted by IV/theta), CE on a candle CLOSE above
# the range high, PE on a close below the range low, underlying-based stop at the opposite
# range edge, 2:1 target projected off the range width, forced exit mid-afternoon, capped at
# one signal per direction per day (so at most 2 trades/day: one CE break, one PE break).
class OrbBreakoutStrategy < BaseStrategy
  IST = 'Asia/Kolkata'

  def call(context)
    series = context.candles.call('5m')
    return Signals::Hold.new(reason: 'no_candle_data') unless series&.candles&.any?

    range_minutes = (params[:range_minutes] || 30).to_i
    min_range_pct = (params[:min_range_pct] || 0.20).to_f
    max_gap_pct   = (params[:max_gap_pct] || 0.80).to_f
    r_multiple    = (params[:target_r_multiple] || 2.0).to_f
    vol_mult      = (params[:volume_multiplier] || 1.5).to_f
    force_hour    = (params[:force_exit_hour] || 14).to_i
    force_minute  = (params[:force_exit_minute] || 30).to_i
    max_failed    = (params[:max_failed_breakouts] || 2).to_i
    strike_pref   = (params[:strike_pref] || 'ATM').to_s

    candles = series.candles
    current = candles.last
    now = current.timestamp.in_time_zone(IST)
    today = now.to_date

    day_candles = candles.select { |c| c.timestamp.in_time_zone(IST).to_date == today }
    return Signals::Hold.new(reason: 'no_day_candles') if day_candles.empty?

    # Hardcode the NSE/BSE cash-session open rather than deriving it from day_candles.first:
    # the context's 6h trailing window can clip the very first candle on late-afternoon
    # evaluations, and 09:15 IST is a fixed constant of the exchange, not derived data.
    session_open = now.change(hour: 9, min: 15, sec: 0)
    range_end = session_open + range_minutes.minutes
    return Signals::Hold.new(reason: 'range_forming') if now < range_end

    range_candles = day_candles.select { |c| c.timestamp.in_time_zone(IST) >= session_open && c.timestamp.in_time_zone(IST) < range_end }
    return Signals::Hold.new(reason: 'range_unavailable') if range_candles.empty?

    orh = range_candles.map(&:high).max
    orl = range_candles.map(&:low).min
    range_width = orh - orl
    return Signals::Hold.new(reason: 'range_unavailable') if range_width <= 0

    ref_price = range_candles.last.close
    if ref_price.positive? && (range_width / ref_price * 100.0) < min_range_pct
      return Signals::Hold.new(reason: 'range_too_narrow')
    end

    gap_hold = gap_filter_hold(day_candles, candles, today, max_gap_pct)
    return gap_hold if gap_hold

    post_range = day_candles.select { |c| c.timestamp.in_time_zone(IST) >= range_end }
    return Signals::Hold.new(reason: 'no_post_range_candles') if post_range.empty?

    prior_bars = post_range[0...-1]
    already_fired = prior_bars.any? { |c| c.close > orh || c.close < orl }
    return Signals::Hold.new(reason: 'already_resolved_today') if already_fired

    failed_breakouts = prior_bars.count do |c|
      (c.high > orh && c.close <= orh) || (c.low < orl && c.close >= orl)
    end
    return Signals::Hold.new(reason: 'two_failed_breakouts') if failed_breakouts >= max_failed

    # DhanHQ reports volume=0 for index candles (see options_buying_backtester.rb's own note
    # on this), which makes avg_volume 0 far more often than not — in that case the filter
    # can't discriminate anything, so we don't gate on it rather than silently blocking or
    # silently always-passing on a divide-by-zero.
    avg_volume = range_candles.sum(&:volume) / range_candles.size.to_f
    volume_ok = avg_volume <= 0 || current.volume >= (avg_volume * vol_mult)

    force_exit_time = now.change(hour: force_hour, min: force_minute, sec: 0)
    exit_rules_for = lambda do |stop, target|
      { stop_index_level: stop, target_index_level: target, force_exit_time: force_exit_time, giveback_enabled: false }
    end

    if current.close > orh
      return Signals::Hold.new(reason: 'volume_filter') unless volume_ok

      target = current.close + (r_multiple * range_width)
      return Signals::BuyCall.new(
        confidence: 0.6,
        reason: "orb_breakout_up range=#{range_width.round(1)} orh=#{orh.round(1)}",
        metadata: { strike_pref: strike_pref, exit_rules: exit_rules_for.call(orl, target) }
      )
    elsif current.close < orl
      return Signals::Hold.new(reason: 'volume_filter') unless volume_ok

      target = current.close - (r_multiple * range_width)
      return Signals::BuyPut.new(
        confidence: 0.6,
        reason: "orb_breakout_down range=#{range_width.round(1)} orl=#{orl.round(1)}",
        metadata: { strike_pref: strike_pref, exit_rules: exit_rules_for.call(orh, target) }
      )
    end

    Signals::Hold.new(reason: 'inside_range')
  end

  private

  def gap_filter_hold(day_candles, all_candles, today, max_gap_pct)
    first_today = day_candles.first
    return nil if first_today.nil?

    prev_day_candles = all_candles.select { |c| c.timestamp.in_time_zone(IST).to_date < today }
    prev_close = prev_day_candles.last&.close
    return nil unless prev_close&.positive?

    gap_pct = ((first_today.open - prev_close).abs / prev_close) * 100.0
    Signals::Hold.new(reason: 'gap_too_large') if gap_pct > max_gap_pct
  end
end
