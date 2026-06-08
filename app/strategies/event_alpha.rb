# frozen_string_literal: true

class EventAlpha < AlphaStrategy
  # [month, day] => [name, impact, bias]
  # bias: :ce, :pe, or nil (detect trend)
  EVENT_CALENDAR = {
    [2, 1]  => ["Union Budget", :high, nil],
    [4, 4]  => ["RBI Policy", :high, nil],
    [6, 8]  => ["RBI Policy", :high, nil],
    [8, 15] => ["Independence Day", :low, nil],
    [10, 2] => ["Q2 Earnings", :medium, nil]
  }.freeze

  ENTRY_WINDOW_HOURS = 24

  def scan
    return nil unless enabled?

    event = upcoming_event
    return nil unless event

    _name, impact, bias = event
    hours_to_event = hours_until_event(event)

    # Only enter within the window before the event
    return nil unless hours_to_event.between?(0, ENTRY_WINDOW_HOURS)

    ltp = underlying_ltp
    return nil unless ltp

    direction = bias || detect_bias_from_trend
    strike = atm_strike(ltp)

    sl_pct = case impact
             when :high then 0.015
             when :medium then 0.02
             else 0.025
             end

    sl_points = (ltp * sl_pct).round(2)
    target_points = (sl_points * 2).round(2)

    build_signal(
      direction: direction,
      strike: strike,
      option_type: :atm,
      entry_price: ltp,
      stop_loss: direction == :ce ? ltp - sl_points : ltp + sl_points,
      target: direction == :ce ? ltp + target_points : ltp - target_points,
      trailing_jump: 0,
      confidence: impact == :high ? 0.75 : 0.60,
      alpha_source: :event,
      iv_context: { event_name: event[0], hours_to_event: hours_to_event, impact: impact }
    )
  end

  private

  def upcoming_event
    today = Date.current
    EVENT_CALENDAR.find do |(month, day), _|
      event_date = Date.new(today.year, month, day)
      event_date >= today && event_date <= today + 2
    end&.last
  end

  def hours_until_event(event)
    today = Date.current
    month, day = EVENT_CALENDAR.key(event)
    event_date = Date.new(today.year, month, day)
    ((event_date.to_time - Time.current) / 3600).round
  end

  def detect_bias_from_trend
    bars = fetch_historical_bars(interval: 5, count: 10)
    return :ce if bars.empty?
    closes = bars.map { |b| b[:close] || b['close'] || 0 }
    closes.last > closes.first ? :ce : :pe
  end
end
