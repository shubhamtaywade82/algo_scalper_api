# frozen_string_literal: true

class ExpiryAlpha < AlphaStrategy
  MAX_ENTRY_HOUR = 14
  MAX_HOLD_MINUTES = 15

  def scan
    return nil unless enabled?
    return nil unless expiry_today?

    now = Time.current.in_time_zone('Asia/Kolkata')
    # Avoid the very end of the day or lunch chop
    return nil if now.hour >= MAX_ENTRY_HOUR || now.hour < 10

    ltp = underlying_ltp
    return nil unless ltp

    bars = fetch_historical_bars(interval: 1, count: 10)
    direction = detect_micro_momentum(bars)
    return nil unless direction

    strike = atm_strike(ltp)
    sl_points = 5.0 # Fixed small point SL for expiry moves
    target_points = 15.0 # 1:3 RR

    build_signal(
      direction: direction,
      strike: strike,
      option_type: :atm,
      entry_price: ltp,
      stop_loss: direction == :ce ? ltp - sl_points : ltp + sl_points,
      target: direction == :ce ? ltp + target_points : ltp - target_points,
      trailing_jump: 3,
      confidence: 0.52,
      alpha_source: :expiry,
      iv_context: { minutes_to_expiry: minutes_to_expiry, gamma: "high" }
    )
  end

  private

  def expiry_today?
    nearest = nearest_expiry
    return false unless nearest
    Date.parse(nearest.to_s) == Time.zone.today
  end

  def minutes_to_expiry
    expiry_time = Time.current.in_time_zone('Asia/Kolkata').change(hour: 15, min: 30)
    ((expiry_time - Time.current) / 60).round
  end

  def detect_micro_momentum(bars)
    return nil if bars.size < 5
    prices = bars.last(5).map { |b| b[:close] || b['close'] || 0 }
    if prices.each_cons(2).all? { |a, b| b > a }
      :ce
    elsif prices.each_cons(2).all? { |a, b| b < a }
      :pe
    end
  end
end
