# frozen_string_literal: true

class CandleSeries
  include Enumerable

  attr_reader :symbol, :interval, :candles

  def initialize(symbol:, interval: "5")
    @symbol = symbol
    @interval = interval
    @candles = []
  end

  def each(&block)
    candles.each(&block)
  end

  def add_candle(candle)
    candles << candle
  end

  def load_from_raw(response)
    normalise_candles(response).each do |row|
      add_candle(
        Candle.new(
          ts: coerce_timestamp(row[:timestamp]),
          open: row[:open],
          high: row[:high],
          low: row[:low],
          close: row[:close],
          volume: row[:volume]
        )
      )
    end
  end

  def normalise_candles(resp)
    return [] if resp.blank?

    return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

    unless resp.is_a?(Hash) && resp["high"].respond_to?(:size)
      raise "Unexpected candle format: #{resp.class}"
    end

    size = resp["high"].size
    (0...size).map do |i|
      {
        open: resp["open"][i].to_f,
        close: resp["close"][i].to_f,
        high: resp["high"][i].to_f,
        low: resp["low"][i].to_f,
        timestamp: resp["timestamp"][i],
        volume: resp["volume"][i].to_i
      }
    end
  end

  def slice_candle(candle)
    if candle.is_a?(Hash)
      {
        open: candle[:open] || candle["open"],
        close: candle[:close] || candle["close"],
        high: candle[:high] || candle["high"],
        low: candle[:low] || candle["low"],
        timestamp: candle[:timestamp] || candle["timestamp"],
        volume: candle[:volume] || candle["volume"] || 0
      }
    elsif candle.respond_to?(:[]) && candle.size >= 6
      {
        timestamp: candle[0],
        open: candle[1],
        high: candle[2],
        low: candle[3],
        close: candle[4],
        volume: candle[5]
      }
    else
      raise "Unexpected candle format: #{candle.inspect}"
    end
  end

  def opens
    candles.map(&:open)
  end

  def closes
    candles.map(&:close)
  end

  def highs
    candles.map(&:high)
  end

  def lows
    candles.map(&:low)
  end

  def to_hash
    {
      "timestamp" => candles.map { |c| c.timestamp.to_i },
      "open" => opens,
      "high" => highs,
      "low" => lows,
      "close" => closes,
      "volume" => candles.map(&:volume)
    }
  end

  def hlc
    candles.each_with_index.map do |c, _i|
      {
        date_time: c.timestamp || Time.zone.at(0),
        high: c.high,
        low: c.low,
        close: c.close
      }
    end
  end

  def atr(period = 14)
    result = TechnicalAnalysis::Atr.calculate(hlc, period: period)
    entry = Array(result).first
    entry&.respond_to?(:atr) ? entry.atr : nil
  rescue NameError
    nil
  end

  def swing_high?(index, lookback = 2)
    return false if index < lookback || index + lookback >= candles.size

    current = candles[index].high
    left = candles[(index - lookback)...index].map(&:high)
    right = candles[(index + 1)..(index + lookback)].map(&:high)
    current > left.max && current > right.max
  end

  def swing_low?(index, lookback = 2)
    return false if index < lookback || index + lookback >= candles.size

    current = candles[index].low
    left = candles[(index - lookback)...index].map(&:low)
    right = candles[(index + 1)..(index + lookback)].map(&:low)
    current < left.min && current < right.min
  end

  def recent_highs(n = 20)
    candles.last(n).map(&:high)
  end

  def recent_lows(n = 20)
    candles.last(n).map(&:low)
  end

  def previous_swing_high
    highs = recent_highs
    return nil if highs.size < 2

    highs.sort[-2]
  end

  def previous_swing_low
    lows = recent_lows
    return nil if lows.size < 2

    lows.sort[1]
  end

  def liquidity_grab_up?(lookback: 20)
    return false if candles.empty?

    high_now = candles.last.high
    high_prev = previous_swing_high
    return false unless high_prev

    high_now > high_prev &&
      candles.last.close < high_prev &&
      candles.last.bearish?
  end

  def liquidity_grab_down?(lookback: 20)
    return false if candles.empty?

    low_now = candles.last.low
    low_prev = previous_swing_low
    return false unless low_prev

    low_now < low_prev &&
      candles.last.close > low_prev &&
      candles.last.bullish?
  end

  def rsi(period = 14)
    RubyTechnicalAnalysis::RelativeStrengthIndex.new(series: closes, period: period).call
  rescue NameError
    nil
  end

  def moving_average(period = 20)
    RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period)
  rescue NameError
    nil
  end

  def sma(period = 20)
    moving_average(period)&.sma
  end

  def ema(period = 20)
    moving_average(period)&.ema
  end

  def macd(fast_period = 12, slow_period = 26, signal_period = 9)
    RubyTechnicalAnalysis::Macd.new(
      series: closes,
      fast_period: fast_period,
      slow_period: slow_period,
      signal_period: signal_period
    ).call
  rescue NameError
    nil
  end

  def rate_of_change(period = 5)
    return nil if closes.size < period + 1

    closes.each_with_index.map do |price, idx|
      if idx < period
        nil
      else
        previous_price = closes[idx - period]
        (((price - previous_price) / previous_price.to_f) * 100.0)
      end
    end
  end

  def supertrend_signal
    trend_line = Indicators::Supertrend.new(series: self).call
    return nil if trend_line.blank?

    latest_close = closes.last
    latest_trend = trend_line.last

    return :long_entry if latest_close > latest_trend
    return :short_entry if latest_close < latest_trend

    nil
  rescue NameError
    nil
  end

  def inside_bar?(index)
    return false if index < 1 || index >= candles.size

    curr = candles[index]
    prev = candles[index - 1]
    curr.high < prev.high && curr.low > prev.low
  end

  def bollinger_bands(period: 20)
    return nil if candles.size < period

    bb = RubyTechnicalAnalysis::BollingerBands.new(
      series: closes,
      period: period
    ).call

    { upper: bb[0], lower: bb[1], middle: bb[2] }
  rescue NameError
    nil
  end

  def donchian_channel(period: 20)
    return nil if candles.size < period

    dc = candles.each_with_index.map do |c, _i|
      {
        date_time: c.timestamp || Time.zone.at(0),
        value: c.close
      }
    end
    TechnicalAnalysis::Dc.calculate(dc, period: period)
  rescue NameError
    nil
  end

  def obv
    candles.each_with_index.map do |c, _i|
      {
        date_time: c.timestamp || Time.zone.at(0),
        close: c.close,
        volume: c.volume || 0
      }
    end
  end

  def on_balance_volume
    data = obv
    TechnicalAnalysis::Obv.calculate(data)
  rescue NameError
    nil
  end

  private

  def coerce_timestamp(value)
    case value
    when ActiveSupport::TimeWithZone, Time
      value
    when DateTime
      value.to_time.in_time_zone
    when Integer
      Time.zone.at(value)
    when Float
      Time.zone.at(value)
    else
      Integer(value)
      Time.zone.at(value.to_i)
    end
  rescue ArgumentError, TypeError
    value.present? ? Time.zone.parse(value.to_s) : nil
  end
end
