# frozen_string_literal: true

class MomentumAlpha < AlphaStrategy
  def scan
    return nil unless enabled?
    return nil unless market_open?

    bars = fetch_historical_bars(interval: 5, count: 20)
    return nil if bars.size < 20

    ltp = underlying_ltp
    return nil unless ltp

    atr = calculate_atr(bars, period: 14)
    high_20 = bars.last(20).map { |b| b[:high] || b['high'] || 0 }.max
    low_20  = bars.last(20).map { |b| b[:low]  || b['low']  || 0 }.min

    direction = nil
    if ltp > high_20 * 0.998 && ltp > (bars[-2][:close] || bars[-2]['close'] || 0) * 1.003
      direction = :ce
    elsif ltp < low_20 * 1.002 && ltp < (bars[-2][:close] || bars[-2]['close'] || 0) * 0.997
      direction = :pe
    end

    return nil unless direction

    chain_data = instrument&.fetch_option_chain
    iv_current = extract_atm_iv(chain_data, atm_strike(ltp), direction)
    iv_history = IvSnapshot.historical_iv(index_key: @index_key, days: 30)
    iv_pct = iv_percentile(current_iv: iv_current, history: iv_history)

    # Only trade if IV is not too high (relative) or if IV is expanding
    return nil unless iv_pct < 40 || iv_expanding?(iv_history)

    vol_avg = bars.last(10).sum { |b| b[:volume] || b['volume'] || 0 } / 10.0
    vol_last = bars.last[:volume] || bars.last['volume'] || 0
    return nil if vol_avg > 0 && vol_last < vol_avg * 1.2

    sl_points = (atr * 1.5).round(2)
    target_points = (sl_points * 1.5).round(2)

    build_signal(
      direction: direction,
      strike: atm_strike(ltp),
      option_type: :atm,
      entry_price: ltp,
      stop_loss: direction == :ce ? ltp - sl_points : ltp + sl_points,
      target: direction == :ce ? ltp + target_points : ltp - target_points,
      trailing_jump: (sl_points * 0.5).round,
      confidence: base_confidence(bars, direction, iv_pct),
      alpha_source: :momentum,
      iv_context: { percentile: iv_pct, current: iv_current, history_size: iv_history.size }
    )
  end

  private

  def market_open?
    now = Time.current.in_time_zone('Asia/Kolkata')
    return false if now.saturday? || now.sunday?
    now.hour >= 9 && (now.hour < 15 || (now.hour == 15 && now.min <= 20))
  end

  def extract_atm_iv(chain_data, strike, direction)
    return nil unless chain_data && chain_data[:oc]
    leg = chain_data[:oc][strike.to_f.to_s]
    return nil unless leg
    data = direction == :ce ? leg['ce'] : leg['pe']
    data&.dig('implied_volatility')&.to_f
  end

  def iv_expanding?(history)
    return false if history.size < 2
    history.last(3).each_cons(2).all? { |a, b| b > a }
  end

  def base_confidence(bars, direction, iv_pct)
    base = 0.50
    base += 0.10 if iv_pct < 30
    base += 0.10 if momentum_aligned?(bars, direction)
    base += 0.10 if volume_increasing?(bars)
    base += 0.05 if bars.last(3).all? { |b| (b[:close] || b['close'] || 0) > (b[:open] || b['open'] || 0) } && direction == :ce
    base += 0.05 if bars.last(3).all? { |b| (b[:close] || b['close'] || 0) < (b[:open] || b['open'] || 0) } && direction == :pe
    [base, 0.95].min
  end

  def momentum_aligned?(bars, direction)
    closes = bars.last(5).map { |b| b[:close] || b['close'] || 0 }
    return false if closes.size < 5
    if direction == :ce
      closes.each_cons(2).all? { |a, b| b > a }
    else
      closes.each_cons(2).all? { |a, b| b < a }
    end
  end

  def volume_increasing?(bars)
    vols = bars.last(5).map { |b| b[:volume] || b['volume'] || 0 }
    vols.each_cons(2).all? { |a, b| b >= a }
  end
end
