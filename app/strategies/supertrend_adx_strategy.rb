# app/strategies/supertrend_adx_strategy.rb
# frozen_string_literal: true

class SupertrendAdxStrategy
  attr_reader :series, :supertrend_cfg, :adx_min_strength

  def initialize(series:, supertrend_cfg:, adx_min_strength: 20)
    @series = series
    @supertrend_cfg = supertrend_cfg
    @adx_min_strength = adx_min_strength
    @supertrend_result = nil
    @supertrend_calculated = false
  end

  # Generates entry signal at given candle index
  # Returns: { type: :ce/:pe, confidence: 0-100 } or nil
  def generate_signal(index)
    return nil if index < supertrend_cfg[:period] # Need enough bars for indicator calculation
    return nil unless trading_hours?(series.candles[index])

    # Calculate Supertrend once for the entire series (cached)
    calculate_supertrend_once unless @supertrend_calculated

    return nil if @supertrend_result.nil? || @supertrend_result[:trend].nil?

    # Get trend at current index
    trend_at_index = get_trend_at_index(index)
    return nil if trend_at_index.nil?

    # Calculate ADX from candles up to current index
    partial_candles = series.candles[0..index]
    adx_value = calculate_adx(partial_candles, 14)
    return nil if adx_value.nil? || adx_value < adx_min_strength

    # Determine direction from supertrend
    direction = trend_at_index == :bullish ? :ce : :pe

    confidence = calculate_confidence(@supertrend_result, adx_value)

    confidence >= 60 ? { type: direction, confidence: confidence } : nil
  end

  private

  def calculate_supertrend_once
    # Calculate Supertrend once for the entire series
    st_service = Indicators::Supertrend.new(series: series, **supertrend_cfg)
    @supertrend_result = st_service.call
    @supertrend_calculated = true
  end

  def get_trend_at_index(index)
    return nil if @supertrend_result.nil?
    return nil if index >= @supertrend_result[:line].size

    # Determine trend at specific index by comparing close to supertrend line
    close = series.candles[index].close
    supertrend_value = @supertrend_result[:line][index]
    return nil if close.nil? || supertrend_value.nil?

    close >= supertrend_value ? :bullish : :bearish
  end

  def trading_hours?(candle)
    hour = candle.timestamp.hour
    minute = candle.timestamp.min

    # Active between 10:00 AM and 2:30 PM
    return false if hour < 10
    return false if hour > 14
    return false if hour == 14 && minute > 30

    true
  end

  def calculate_confidence(supertrend_result, adx)
    base = 50
    base += 30 if supertrend_result[:trend]
    base += 10 if adx > 30
    [base, 100].min
  end

  def calculate_adx(candles, period)
    return nil if candles.size < period + 1

    trs = []
    plus_dm = []
    minus_dm = []

    candles.each_cons(2) do |prev, curr|
      high = curr.high
      low = curr.low
      prev_close = prev.close

      tr = [high - low, (high - prev_close).abs, (low - prev_close).abs].max
      trs << tr

      up_move = high - prev.high
      down_move = prev.low - low

      plus_dm << (up_move > down_move && up_move.positive? ? up_move : 0)
      minus_dm << (down_move > up_move && down_move.positive? ? down_move : 0)
    end

    atr = trs.last(period).sum / period
    di_plus = 100 * (plus_dm.last(period).sum / period) / atr
    di_minus = 100 * (minus_dm.last(period).sum / period) / atr
    ((di_plus - di_minus).abs / (di_plus + di_minus)) * 100
  end
end
