# frozen_string_literal: true

class CandleSeries
  include Enumerable

  attr_reader :symbol, :interval, :candles

  def initialize(symbol:, interval: "5")
    @symbol = symbol
    @interval = interval
    @candles = []
  end

  def each(&) = candles.each(&)
  def add_candle(candle) = candles << candle

  def load_from_raw(response)
    normalise_candles(response).each do |row|
      @candles << Candle.new(
        ts: Time.zone.parse(row[:timestamp].to_s),
        open: row[:open], high: row[:high],
        low: row[:low], close: row[:close],
        volume: row[:volume]
      )
    end
  end

  def normalise_candles(resp)
    return [] if resp.blank?

    return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

    raise "Unexpected candle format: #{resp.class}" unless resp.is_a?(Hash) && resp["high"].is_a?(Array)

    size = resp["high"].size
    (0...size).map do |i|
      {
        open: resp["open"][i].to_f,
        close: resp["close"][i].to_f,
        high: resp["high"][i].to_f,
        low: resp["low"][i].to_f,
        timestamp: Time.zone.at(resp["timestamp"][i]),
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

  def opens  = candles.map(&:open)
  def closes = candles.map(&:close)
  def highs  = candles.map(&:high)
  def lows   = candles.map(&:low)

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
        date_time: Time.zone.at(c.timestamp || 0),
        high: c.high,
        low: c.low,
        close: c.close
      }
    end
  end

  def atr(period = 14)
    TechnicalAnalysis::Atr.calculate(hlc, period: period).first.atr
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
    values = recent_highs
    return nil if values.size < 2

    values.sort[-2]
  end

  def previous_swing_low
    values = recent_lows
    return nil if values.size < 2

    values.sort[1]
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
    return nil if candles.empty?
    RubyTechnicalAnalysis::RelativeStrengthIndex.new(series: closes, period: period).call
  end

  def moving_average(period = 20)
    return nil if candles.empty?
    RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period)
  end

  def sma(period = 20)
    return nil if candles.empty?
    moving_average(period)&.sma
  end

  def ema(period = 20)
    return nil if candles.empty?
    moving_average(period)&.ema
  end

  def macd(fast_period = 12, slow_period = 26, signal_period = 9)
    macd = RubyTechnicalAnalysis::Macd.new(series: closes, fast_period: fast_period, slow_period: slow_period, signal_period: signal_period)
    macd.call
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
    result = Indicators::Supertrend.new(series: self).call
    trend_line = result[:line] || []
    return nil if trend_line.empty?

    case result[:trend]
    when :bullish
      return :long_entry
    when :bearish
      return :short_entry
    end

    latest_index = trend_line.rindex { |value| !value.nil? }
    return nil if latest_index.nil?

    latest_close = closes[latest_index]
    latest_trend = trend_line[latest_index]
    return nil if latest_close.nil? || latest_trend.nil?

    return :long_entry if latest_close > latest_trend

    :short_entry if latest_close < latest_trend
  end

  def inside_bar?(i)
    return false if i < 1

    curr = @candles[i]
    prev = @candles[i - 1]
    curr.high < prev.high && curr.low > prev.low
  end

  def bollinger_bands(period: 20, std_dev: 2.0)
    return nil if candles.size < period

    bb = RubyTechnicalAnalysis::BollingerBands.new(
      series: closes,
      period: period
    ).call

    { upper: bb[0], lower: bb[1], middle: bb[2] }
  end

  def donchian_channel(period: 20)
    return nil if candles.size < period

    dc = candles.each_with_index.map do |c, _i|
      {
        date_time: Time.zone.at(c.timestamp || 0),
        value: c.close
      }
    end
    TechnicalAnalysis::Dc.calculate(dc, period: period)
  end

  def obv
    dcv = candles.each_with_index.map do |c, _i|
      {
        date_time: Time.zone.at(c.timestamp || 0),
        close: c.close,
        volume: c.volume || 0
      }
    end

    TechnicalAnalysis::Obv.calculate(dcv)
  end
end
