# frozen_string_literal: true

# rubocop:disable-next Metrics/ClassLength
class CandleSeries
  include Enumerable

  MAX_CANDLES = 200

  attr_reader :symbol, :interval, :candles

  def initialize(symbol:, interval: '5')
    @symbol = symbol
    @interval = interval
    @candles = []
  end

  def each(&) = candles.each(&)

  def add_candle(candle)
    candles << candle
    candles.shift if candles.size > MAX_CANDLES
    candle
  end

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

  # Strict numeric parse for market data (error-handling review 2026-09).
  # Ruby's `.to_f` is permissive: nil and "abc" silently became 0.0, so a
  # corrupt candle collapsed toward a zero-like price instead of failing.
  # Zero is a meaningful financial value — it must never be a fallback.
  #
  # @raise [Errors::InvalidMarketData]
  # @return [Float]
  def parse_price!(value, field:, index: nil)
    case value
    when Numeric
      unless value.respond_to?(:finite?) && value.finite?
        raise Errors::InvalidMarketData, "candle #{field}#{"[#{index}]" if index} is not finite: #{value.inspect}"
      end

      value.to_f
    when String
      unless value.strip.match?(NUMERIC_PATTERN)
        raise Errors::InvalidMarketData, "candle #{field}#{"[#{index}]" if index} is not numeric: #{value.inspect}"
      end

      value.to_f
    else
      raise Errors::InvalidMarketData, "candle #{field}#{"[#{index}]" if index} is missing/not numeric: #{value.inspect}"
    end
  end

  def normalize_hash_format(resp)
    raise "Unexpected candle format: #{resp.class}" unless resp.is_a?(Hash) && resp['high'].is_a?(Array)

    %w[open high low close].each do |key|
      next if resp[key].is_a?(Array)

      raise Errors::InvalidMarketData, "candle payload is missing the '#{key}' array"
    end

    size = resp['high'].size
    (0...size).map do |i|
      timestamp = (resp['timestamp'] || [])[i]
      raise Errors::InvalidMarketData, "candle timestamp[#{i}] is missing" if timestamp.nil?

      {
        open: parse_price!(resp['open'][i], field: 'open', index: i),
        close: parse_price!(resp['close'][i], field: 'close', index: i),
        high: parse_price!(resp['high'][i], field: 'high', index: i),
        low: parse_price!(resp['low'][i], field: 'low', index: i),
        timestamp: Time.zone.at(timestamp),
        # Volume is the one documented exception: index feeds legitimately
        # deliver volumeless candles (key absent), so missing -> 0 is a
        # representation decision, not a fallback for corrupt data.
        # Non-numeric garbage still raises via the strict parse below.
        volume: parse_volume!((resp['volume'] || [])[i], index: i)
      }
    end
  end

  # @raise [Errors::InvalidMarketData]
  # @return [Integer]
  def parse_volume!(value, index: nil)
    return 0 if value.nil?

    case value
    when Integer then value
    when Float, BigDecimal
      unless value.respond_to?(:finite?) && value.finite?
        raise Errors::InvalidMarketData, "candle volume[#{index}] is not finite: #{value.inspect}"
      end

      value.to_i
    when String
      unless value.strip.match?(INTEGER_PATTERN)
        raise Errors::InvalidMarketData, "candle volume[#{index}] is not an integer: #{value.inspect}"
      end

      value.to_i
    else
      raise Errors::InvalidMarketData, "candle volume[#{index}] is not numeric: #{value.inspect}"
    end
  end

  NUMERIC_PATTERN = /\A[+-]?\d+(\.\d+)?([eE][+-]?\d+)?\z/
  INTEGER_PATTERN = /\A[+-]?\d+\z/

  # Representation adapter for the two known candle payload shapes
  # (symbol-keyed vs string-keyed hashes, plus positional arrays), followed
  # by STRICT validation: previously a candle whose :open was missing in both
  # representations flowed through as nil and detonated deep inside an
  # indicator. Malformed candles now fail at the boundary with the field named.
  #
  # @raise [Errors::InvalidMarketData]
  def slice_candle(candle)
    sliced =
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

    %i[open high low close timestamp].each do |field|
      next if sliced[field].present?

      raise Errors::InvalidMarketData, "candle field #{field.inspect} missing: #{candle.inspect[0, 200]}"
    end

    sliced[:volume] = parse_volume!(sliced[:volume])
    sliced
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

  # VWAP over the candle window. Contract (error-handling review 2026-09):
  # when cumulative volume is zero VWAP is mathematically UNDEFINED — the
  # previous code substituted the typical price, which is a different number
  # wearing VWAP's name. Zero-volume prefixes now yield nil; consumers
  # treat nil as "VWAP not yet available".
  #
  # @return [Array<Float, nil>] per-candle VWAP; nil where volume has not started
  def vwap
    return [] if candles.empty?

    cum_pv = 0.0
    cum_v = 0.0

    candles.map do |c|
      typical_price = (c.high + c.low + c.close) / 3.0
      cum_pv += typical_price * c.volume
      cum_v += c.volume
      cum_v.positive? ? (cum_pv / cum_v).round(2) : nil
    end
  end

  def current_vwap
    vwap.last
  end

  # ATR. Return contract: nil ONLY for the documented domain outcome
  # "not enough candles / invalid input shape for the gem". Unexpected
  # calculation errors now PROPAGATE instead of collapsing to nil — a
  # strategy reading nil must never have to wonder whether the gem broke.
  #
  # @return [Float, nil]
  def atr(period = 14)
    return nil if candles.size < period + 1

    result = TechnicalAnalysis::Atr.calculate(hlc, period: period)
    return nil if result.empty?

    result.last.atr
  rescue TechnicalAnalysis::Validation::ValidationError, ArgumentError, TypeError => e
    Rails.logger.warn("[CandleSeries] ATR not computable: #{e.message}")
    nil
  end

  # ADX. Same contract as #atr: nil only for insufficient/invalid input;
  # unexpected errors propagate.
  #
  # @return [Float, nil]
  def adx(period = 14)
    # ADX needs at least period + 1 candles, but TechnicalAnalysis gem typically needs 2*period for accuracy
    # We'll check for period + 1 here (minimum), but callers should ensure 2*period for best results
    return nil if candles.size < period + 1

    result = TechnicalAnalysis::Adx.calculate(hlc, period: period)
    return nil if result.empty?

    result.last.adx
  rescue TechnicalAnalysis::Validation::ValidationError, ArgumentError, TypeError => e
    # "Not enough data" is expected when called early in a session — debug, not warn
    unless e.message.to_s.include?('Not enough data') || e.message.to_s.include?('insufficient')
      Rails.logger.warn("[CandleSeries] ADX not computable: #{e.message}")
    end
    nil
  end

  def swing_high?(index, lookback = 3)
    return false if index < lookback || index + lookback >= candles.size

    current = candles[index].high
    left = candles[(index - lookback)...index].map(&:high)
    right = candles[(index + 1)..(index + lookback)].map(&:high)
    current > left.max && current > right.max
  end

  def swing_low?(index, lookback = 3)
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

  # RSI. Same contract as #atr: nil only for insufficient/invalid input.
  #
  # @return [Float, nil]
  def rsi(period = 14)
    return nil if candles.empty?

    RubyTechnicalAnalysis::RelativeStrengthIndex.new(series: closes, period: period).call
  rescue TechnicalAnalysis::Validation::ValidationError, ArgumentError, TypeError => e
    Rails.logger.warn("[CandleSeries] RSI not computable: #{e.message}")
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

  # MACD. Same contract as #atr: nil only for insufficient/invalid input.
  #
  # @return [Array(Float, Float, Float), nil] [macd, signal, histogram]
  def macd(fast_period = 12, slow_period = 26, signal_period = 9)
    return nil if candles.empty?
    return nil if closes.size < slow_period + signal_period

    macd = RubyTechnicalAnalysis::Macd.new(series: closes, fast_period: fast_period, slow_period: slow_period,
                                           signal_period: signal_period)
    result = macd.call
    return nil if result.nil? || !result.is_a?(Array) || result.size < 3

    result # Returns [macd, signal, histogram] array
  rescue TechnicalAnalysis::Validation::ValidationError, ArgumentError, TypeError => e
    Rails.logger.warn("[CandleSeries] MACD not computable: #{e.message}")
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

  # Supertrend signal. Default resolution is EXPLICIT (error-handling
  # review 2026-09): the method signature is the single authoritative source
  # of defaults; supertrend_cfg only ever OVERRIDES, it never fills gaps with
  # hidden magic numbers.
  def supertrend_signal(period: 7, multiplier: 3.0, supertrend_cfg: {})
    cfg = supertrend_cfg.is_a?(Hash) ? supertrend_cfg.dup : {}
    cfg[:period] ||= period
    cfg[:base_multiplier] ||= multiplier

    result = Indicators::Supertrend.new(series: self, **cfg).call
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

  # OBV. Same contract as #atr: nil only for insufficient/invalid input.
  #
  # @return [Array, nil]
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
  rescue TechnicalAnalysis::Validation::ValidationError, ArgumentError, TypeError => e
    Rails.logger.warn("[CandleSeries] OBV not computable: #{e.message}")
    nil
  end
end
