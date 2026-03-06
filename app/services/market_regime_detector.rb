# frozen_string_literal: true

# A stateless, real-time market regime detector tailored for Option Buying systems.
# Classifies the market into RANGING, TRENDING_UP, TRENDING_DOWN, or CHOPPY based on volatility and momentum.
class MarketRegimeDetector
  # Configuration parameters (tuned for Indian indices like Nifty/BankNifty using 5m/15m/30m timeframes)
  VOLATILITY_THRESHOLD = 0.008      # 0.8% ATR relative to price (defines high vs low volatility)
  TREND_STRENGTH = 65.0             # ADX threshold for strong trend (0-100 scale in TechnicalAnalysis gem)
  MIN_CANDLES = 20                  # Minimum candles required for accurate ADX/BB/ATR calculations

  attr_reader :series, :symbol, :timeframe

  # @param series [CandleSeries] A populated CandleSeries instance containing recent OHLCV data.
  def initialize(series)
    @series = series
    @symbol = series.symbol
    @timeframe = series.interval
  end

  # Primary regime detector - checks cache first, then computes if necessary
  # @return [Hash] containing :regime, :confidence, and verbose :metrics
  def detect
    return { regime: 'INSUFFICIENT_DATA', confidence: 0 } if series.candles.size < MIN_CANDLES

    cached = cached_regime
    return cached if cached

    regime_data = compute_regime
    cache_regime(regime_data)
    regime_data
  end

  private

  def cache_key
    "market_regime:#{symbol}:#{timeframe}"
  end

  def cached_regime
    data = Rails.cache.read(cache_key)
    return nil unless data

    # Needs indifferent access or string keys logic. Rails.cache handles native hashes well.
    data
  rescue StandardError => e
    Rails.logger.error("[MarketRegimeDetector] Cache read failed: #{e.message}")
    nil
  end

  def cache_regime(regime)
    # Cache regime for a very short duration (e.g., 2 minutes) since it's real-time intraday
    Rails.cache.write(cache_key, regime, expires_in: 2.minutes)
  rescue StandardError => e
    Rails.logger.error("[MarketRegimeDetector] Cache write failed: #{e.message}")
  end

  def compute_regime
    # Ensure chronological order before calculating indicators
    series.ensure_sorted!

    metrics = calculate_metrics

    case
    when trending?(metrics)
      trend_direction(metrics)
    when ranging?(metrics)
      { regime: 'RANGING', confidence: (100 - metrics[:adx_value]).round(2) }
    else
      { regime: 'CHOPPY', confidence: 50.0 } # Needs more confirmation
    end.merge(metrics: metrics, timestamp: Time.current.iso8601)
  end

  def calculate_metrics
    adx_val = series.adx(14) || 0.0
    atr_val = series.atr(14) || 0.0
    current_price = series.candles.last.close.to_f

    # Guard against zero price division
    atr_percent = current_price > 0 ? (atr_val / current_price) : 0.0

    {
      current_price: current_price,
      atr_percent: atr_percent.round(4),
      adx_value: adx_val.round(2),
      bb_breakout: bollinger_band_breakout?,
      price_position: price_in_range,
      volatility_regime: iv_regime(atr_percent)
    }
  end

  def trending?(metrics)
    # Trending if ADX is strong
    metrics[:adx_value] >= TREND_STRENGTH
  end

  def ranging?(metrics)
    # Ranging if volatility is low, ADX indicates lack of trend, and no breakout has occurred
    metrics[:atr_percent] < VOLATILITY_THRESHOLD &&
      metrics[:adx_value] < 40.0 &&
      !metrics[:bb_breakout]
  end

  def trend_direction(metrics)
    # Determine UP vs DOWN based on where the current price sits relative to recent high/low range
    direction = metrics[:price_position] > 0.6 ? 'UP' : 'DOWN'
    { regime: "TRENDING_#{direction}", confidence: metrics[:adx_value] }
  end

  def bollinger_band_breakout?
    # Uses 20-period BB with 2.0 std dev
    bb = series.bollinger_bands(period: 20, std_dev: 2.0)
    return false unless bb && bb[:upper] && bb[:lower]

    current_close = series.candles.last.close.to_f

    # We define a breakout as closing outside the bands
    current_close > bb[:upper] || current_close < bb[:lower]
  end

  def price_in_range
    # Calculate where current price is relative to the recent high/low range (e.g. last 20 candles)
    recent_high = series.recent_highs(20).max.to_f
    recent_low = series.recent_lows(20).min.to_f

    range = recent_high - recent_low
    return 0.5 if range <= 0.0 # Prevent division by zero if completely flat

    current_close = series.candles.last.close.to_f

    # Returns 0.0 (at absolute bottom) to 1.0 (at absolute top)
    ((current_close - recent_low) / range).round(2)
  end

  def iv_regime(atr_percent)
    # Proxy for IV based on realized volatility (ATR)
    atr_percent > 0.01 ? 'HIGH_VOL' : 'LOW_VOL'
  end
end
