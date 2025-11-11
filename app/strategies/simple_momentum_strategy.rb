# app/strategies/simple_momentum_strategy.rb
# frozen_string_literal: true

class SimpleMomentumStrategy
  attr_reader :series

  def initialize(series:)
    @series = series
  end

  # Generates entry signal at given candle index
  # Returns: { type: :ce/:pe, confidence: 0-100 } or nil
  def generate_signal(index)
    return nil if index < 3 # Need at least 3 bars for momentum check
    return nil unless trading_hours?(series.candles[index])

    candle = series.candles[index]
    prev1 = series.candles[index - 1]
    prev2 = series.candles[index - 2]

    # Strategy: Strong directional candle with confirmation

    # CE Signal (Bullish)
    if bullish_setup?(candle, prev1, prev2)
      return { type: :ce, confidence: calculate_confidence(candle, prev1, prev2, :bullish) }
    end

    # PE Signal (Bearish)
    if bearish_setup?(candle, prev1, prev2)
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

  def bullish_setup?(candle, prev1, prev2)
    # Condition 1: Strong green candle (body > 70% of range)
    strong_candle = candle.bullish? && candle_body_percent(candle) > 70

    # Condition 2: Previous 2 candles also green (momentum)
    momentum = prev1.bullish? && prev2.bullish?

    # Condition 3: Closes in top 30% of range
    range = candle.high - candle.low
    return false if range.zero?

    closes_high = (candle.close - candle.low) / range > 0.70

    strong_candle && momentum && closes_high
  end

  def bearish_setup?(candle, prev1, prev2)
    # Condition 1: Strong red candle (body > 70% of range)
    strong_candle = candle.bearish? && candle_body_percent(candle) > 70

    # Condition 2: Previous 2 candles also red (momentum)
    momentum = prev1.bearish? && prev2.bearish?

    # Condition 3: Closes in bottom 30% of range
    range = candle.high - candle.low
    return false if range.zero?

    closes_low = (candle.close - candle.low) / range < 0.30

    strong_candle && momentum && closes_low
  end

  def candle_body_percent(candle)
    range = candle.high - candle.low
    return 0 if range.zero?

    body = (candle.close - candle.open).abs
    (body / range * 100).round(2)
  end

  def calculate_confidence(candle, prev1, prev2, direction)
    confidence = 50 # Base

    # Add confidence for strong body
    body_pct = candle_body_percent(candle)
    confidence += 10 if body_pct > 80
    confidence += 5 if body_pct > 75

    # Add confidence for consistent momentum
    if direction == :bullish
      confidence += 10 if prev1.close > prev2.close
      confidence += 10 if candle.close > prev1.high
    else
      confidence += 10 if prev1.close < prev2.close
      confidence += 10 if candle.close < prev1.low
    end

    # Add confidence for volume (if available)
    if candle.volume > 0 && prev1.volume > 0
      confidence += 10 if candle.volume > prev1.volume * 1.2
    end

    [confidence, 100].min
  end
end