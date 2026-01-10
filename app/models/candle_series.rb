# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
class CandleSeries
  include Enumerable

  attr_reader :symbol, :interval, :candles

  def initialize(symbol:, interval: '5')
    @symbol = symbol
    @interval = interval
    @candles = []
  end

  def each(&) = candles.each(&)
  def add_candle(candle) = candles << candle

  # Ensures candles are sorted by timestamp (chronological order)
  # CRITICAL: All indicators (Supertrend, ADX, ATR, RSI, MACD) assume chronological order
  # Call this method if candles are added via add_candle and order might be incorrect
  def ensure_sorted!
    @candles.sort_by!(&:timestamp)
  end

  def load_from_raw(response)
    normalise_candles(response).each do |row|
      @candles << Candle.new(
        timestamp: Time.zone.parse(row[:timestamp].to_s),
        open: row[:open], high: row[:high],
        low: row[:low], close: row[:close],
        volume: row[:volume]
      )
    end
    # CRITICAL: Sort candles by timestamp to ensure chronological order
    # All indicators (Supertrend, ADX, ATR, RSI, MACD, etc.) assume chronological order
    # Without sorting, indicator calculations will be incorrect
    @candles.sort_by!(&:timestamp)
  end

  def normalise_candles(resp)
    return [] if resp.blank?

    return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

    normalize_hash_format(resp)
  end

  def normalize_hash_format(resp)
    raise "Unexpected candle format: #{resp.class}" unless resp.is_a?(Hash) && resp['high'].is_a?(Array)

    size = resp['high'].size
    (0...size).map do |i|
      {
        open: resp['open'][i].to_f,
        close: resp['close'][i].to_f,
        high: resp['high'][i].to_f,
        low: resp['low'][i].to_f,
        timestamp: Time.zone.at(resp['timestamp'][i]),
        volume: resp['volume'][i].to_i
      }
    end
  end

  def slice_candle(candle)
    if candle.is_a?(Hash)
      {
        open: candle[:open] || candle['open'],
        close: candle[:close] || candle['close'],
        high: candle[:high] || candle['high'],
        low: candle[:low] || candle['low'],
        timestamp: candle[:timestamp] || candle['timestamp'],
        volume: candle[:volume] || candle['volume'] || 0
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
      'timestamp' => candles.map { |c| c.timestamp.to_i },
      'open' => opens,
      'high' => highs,
      'low' => lows,
      'close' => closes,
      'volume' => candles.map(&:volume)
    }
  end

  def hlc
    # Ensure candles are sorted before building HLC array for TechnicalAnalysis gem
    # ADX, ATR, and other indicators require chronological order
    ensure_sorted! if candles.any? && candles.first.respond_to?(:timestamp)

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
    return nil if candles.size < period + 1

    TechnicalAnalysis::Atr.calculate(hlc, period: period).first.atr
  rescue TechnicalAnalysis::Validation::ValidationError, ArgumentError, TypeError => e
    Rails.logger.warn("[CandleSeries] ATR calculation failed: #{e.message}")
    nil
  rescue StandardError => e
    raise if e.is_a?(NoMethodError)

    Rails.logger.warn("[CandleSeries] ATR calculation failed: #{e.message}")
    nil
  end

  def adx(period = 14)
    # ADX needs at least period + 1 candles, but TechnicalAnalysis gem typically needs 2*period for accuracy
    # We'll check for period + 1 here (minimum), but callers should ensure 2*period for best results
    return nil if candles.size < period + 1

    result = TechnicalAnalysis::Adx.calculate(hlc, period: period)
    return nil if result.empty?

    result.last.adx
  rescue ArgumentError, TypeError => e
    # Suppress "Not enough data" warnings - they're expected when called too early
    unless e.message.to_s.include?('Not enough data') || e.message.to_s.include?('insufficient')
      Rails.logger.warn("[CandleSeries] ADX calculation failed: #{e.message}")
    end
    nil
  rescue StandardError => e
    # Don't catch NoMethodError as it indicates programming errors
    raise if e.is_a?(NoMethodError)

    # Suppress "Not enough data" warnings - they're expected when called too early
    unless e.message.to_s.include?('Not enough data') || e.message.to_s.include?('insufficient')
      Rails.logger.warn("[CandleSeries] ADX calculation failed: #{e.message}")
    end
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

  def recent_highs(count = 20)
    candles.last(count).map(&:high)
  end

  def recent_lows(count = 20)
    candles.last(count).map(&:low)
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

  def liquidity_grab_up?(_lookback: 20)
    return false if candles.empty?

    high_now = candles.last.high
    high_prev = previous_swing_high
    return false unless high_prev

    high_now > high_prev &&
      candles.last.close < high_prev &&
      candles.last.bearish?
  end

  def liquidity_grab_down?(_lookback: 20)
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
  rescue ArgumentError, TypeError => e
    Rails.logger.warn("[CandleSeries] RSI calculation failed: #{e.message}")
    nil
  rescue StandardError => e
    raise if e.is_a?(NoMethodError)

    Rails.logger.warn("[CandleSeries] RSI calculation failed: #{e.message}")
    nil
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
    return nil if candles.empty?
    return nil if closes.size < slow_period + signal_period

    macd = RubyTechnicalAnalysis::Macd.new(series: closes, fast_period: fast_period, slow_period: slow_period,
                                           signal_period: signal_period)
    result = macd.call
    return nil if result.nil? || !result.is_a?(Array) || result.size < 3

    result # Returns [macd, signal, histogram] array
  rescue NoMethodError => e
    raise e
  rescue StandardError => e
    Rails.logger.warn("[CandleSeries] MACD calculation failed: #{e.message}")
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

  def inside_bar?(index)
    return false if index < 1

    curr = @candles[index]
    prev = @candles[index - 1]
    curr.high < prev.high && curr.low > prev.low
  end

  def bollinger_bands(period: 20, std_dev: 2.0) # rubocop:disable Lint/UnusedMethodArgument
    # std_dev parameter kept for API compatibility but not used by library
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
    return nil if candles.empty?

    dcv = candles.each_with_index.map do |c, _i|
      {
        date_time: Time.zone.at(c.timestamp || 0),
        close: c.close,
        volume: c.volume || 0
      }
    end

    # OBV.calculate is a class method that takes an array of hashes
    # The gem expects the data in a specific format
    TechnicalAnalysis::Obv.calculate(dcv)
  rescue NoMethodError => e
    raise e
  rescue StandardError => e
    # OBV.calculate might have different signature - try alternative approach
    Rails.logger.warn("[CandleSeries] OBV calculation failed: #{e.message}")
    nil
  end
end
# rubocop:enable Metrics/ClassLength
