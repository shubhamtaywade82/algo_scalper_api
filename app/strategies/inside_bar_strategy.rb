# app/strategies/inside_bar_strategy.rb
# frozen_string_literal: true

class InsideBarStrategy
  attr_reader :series

  def initialize(series:)
    @series = series
  end

  # Generates entry signal at given candle index
  # Returns: { type: :ce/:pe, confidence: 0-100 } or nil
  def generate_signal(index)
    return nil if index < 2 # Need at least 2 bars
    return nil unless trading_hours?(series.candles[index])

    candle = series.candles[index]
    prev1 = series.candles[index - 1]
    prev2 = series.candles[index - 2]

    # Check if prev1 was an inside bar using CandleSeries helper method
    return nil unless series.inside_bar?(index - 1)

    # CE Signal: Breakout above inside bar high
    if candle.high > prev1.high && candle.close > prev1.high
      return { type: :ce, confidence: calculate_confidence(candle, prev1, prev2, :bullish) }
    end

    # PE Signal: Breakout below inside bar low
    if candle.low < prev1.low && candle.close < prev1.low
      return { type: :pe, confidence: calculate_confidence(candle, prev1, prev2, :bearish) }
    end

    nil
  end

  private

  def trading_hours?(candle)
    # Convert timestamp to IST timezone explicitly
    ist_time = candle.timestamp.in_time_zone('Asia/Kolkata')
    hour = ist_time.hour
    minute = ist_time.min

    # Only trade between 10:00 AM - 2:30 PM IST
    return false if hour < 10
    return false if hour > 14
    return false if hour == 14 && minute > 30

    true
  end

  def calculate_confidence(candle, inside_bar, parent, _direction)
    confidence = 60 # Base for inside bar breakout

    # Add confidence for strong breakout candle
    body_pct = candle_body_percent(candle)
    confidence += 10 if body_pct > 70
    confidence += 5 if body_pct > 60

    # Add confidence for clean inside bar (smaller range)
    inside_range = inside_bar.high - inside_bar.low
    parent_range = parent.high - parent.low
    return [confidence, 100].min if parent_range.zero?

    range_ratio = inside_range / parent_range
    confidence += 10 if range_ratio < 0.5 # Inside bar is <50% of parent

    # Add confidence for volume expansion on breakout
    if candle.volume.positive? && inside_bar.volume.positive? && (candle.volume > inside_bar.volume * 1.3)
      confidence += 10
    end

    [confidence, 100].min
  end

  def candle_body_percent(candle)
    range = candle.high - candle.low
    return 0 if range.zero?

    body = (candle.close - candle.open).abs
    (body / range * 100).round(2)
  end
end
