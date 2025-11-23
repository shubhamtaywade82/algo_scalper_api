# frozen_string_literal: true

module Signal
  # Trend scoring service for NEMESIS V3
  # Computes composite trend score (0-21) from multiple factors:
  # - PA_score (0-7): Price action patterns, structure breaks, momentum
  # - IND_score (0-7): Technical indicators (RSI, MACD, ADX, Supertrend)
  # - MTF_score (0-7): Multi-timeframe alignment
  # Note: VOL_score removed - volume is always 0 for indices/underlying spots
  # rubocop:disable Metrics/ClassLength
  class TrendScorer
    attr_reader :instrument, :primary_tf, :confirmation_tf

    def self.compute_direction(index_cfg:, primary_tf: '1m', confirmation_tf: '5m',
                               bullish_threshold: 14.0, bearish_threshold: 7.0)
      instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
      return { direction: nil, trend_score: nil } unless instrument

      scorer = new(instrument: instrument, primary_tf: primary_tf, confirmation_tf: confirmation_tf)
      result = scorer.compute_trend_score
      score = result[:trend_score].to_f

      direction =
        if score >= bullish_threshold
          :bullish
        elsif score <= bearish_threshold
          :bearish
        else
          nil
        end

      { direction: direction, trend_score: score }
    rescue StandardError => e
      Rails.logger.error("[TrendScorer] compute_direction error: #{e.class} - #{e.message}")
      { direction: nil, trend_score: nil }
    end

    def initialize(instrument:, primary_tf: '1m', confirmation_tf: '5m')
      @instrument = instrument
      @primary_tf = normalize_timeframe(primary_tf)
      @confirmation_tf = normalize_timeframe(confirmation_tf)
    end

    # Compute composite trend score
    # @return [Hash] { trend_score: 0-21, breakdown: { pa: 0-7, ind: 0-7, mtf: 0-7, vol: 0.0 } }
    def compute_trend_score
      primary_series = get_series(@primary_tf)
      confirmation_series = get_series(@confirmation_tf) if @confirmation_tf != @primary_tf

      pa = pa_score(primary_series)
      ind = ind_score(primary_series)
      mtf = mtf_score(primary_series, confirmation_series)
      # VOL score removed - volume is always 0 for indices/underlying spots

      trend_score = pa + ind + mtf

      {
        trend_score: trend_score,
        breakdown: {
          pa: pa,
          ind: ind,
          mtf: mtf,
          vol: 0.0
        }
      }
    rescue StandardError => e
      Rails.logger.error("[TrendScorer] Error computing trend score: #{e.class} - #{e.message}")
      {
        trend_score: 0,
        breakdown: { pa: 0, ind: 0, mtf: 0, vol: 0.0 }
      }
    end

    private

    # Normalize timeframe string to interval format
    # @param timeframe [String] Timeframe (e.g., '1m', '5m', '15m')
    # @return [String] Interval string (e.g., '1', '5', '15')
    def normalize_timeframe(timeframe)
      return '5' if timeframe.blank?

      timeframe.to_s.downcase.gsub(/[^0-9]/, '').presence || '5'
    end

    # Get candle series for timeframe
    # @param interval [String] Interval string
    # @return [CandleSeries, nil]
    def get_series(interval)
      return nil unless @instrument.respond_to?(:candle_series)

      @instrument.candle_series(interval: interval)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # Price action score (0-7)
    # Uses: CandleSeries patterns, structure breaks, momentum
    def pa_score(series)
      return 0 unless series&.candles&.any?

      score = 0.0
      candles = series.candles
      closes = normalize_numeric_series(series.closes)
      return 0 if closes.size < 3

      # 1. Momentum (0-2 points)
      # Recent price momentum (last 3 vs previous 3)
      if closes.size >= 6
        recent_avg = closes.last(3).sum / 3.0
        prev_avg = closes[-6..-4].sum / 3.0
        momentum_pct = prev_avg.positive? ? ((recent_avg - prev_avg) / prev_avg * 100) : 0
        if momentum_pct > 1.0
          score += 2.0 # Strong upward momentum
        elsif momentum_pct > 0.3
          score += 1.0 # Moderate momentum
        end
      end

      # 2. Structure breaks (0-2 points)
      # Check for swing highs/lows (structure breaks)
      last_index = candles.size - 1
      if safe_swing_high?(series, last_index, lookback: 2)
        score += 1.0 # Bullish structure break
      end
      if last_index >= 5 && safe_swing_low?(series, last_index - 3, lookback: 2)
        score += 0.5 # Recent swing low (support)
      end

      # 3. Candle patterns (0-2 points)
      last_candle = candles.last
      if last_candle
        # Bullish candle patterns
        if last_candle.bullish? && last_candle.close > last_candle.open * 1.01
          score += 1.0 # Strong bullish candle
        elsif last_candle.bullish?
          score += 0.5 # Bullish candle
        end
        # Higher high pattern
        if candles.size >= 2 && last_candle.high > candles[-2].high
          score += 0.5 # Higher high
        end
      end

      # 4. Trend consistency (0-1 point)
      # Check if closes are generally increasing
      if closes.size >= 5
        increasing_count = closes.last(5).each_cons(2).count { |a, b| b > a }
        if increasing_count >= 4
          score += 1.0 # Very consistent uptrend
        elsif increasing_count >= 3
          score += 0.5 # Mostly increasing
        end
      end

      score.clamp(0.0, 7.0).round(1)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # Indicator score (0-7)
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # Uses: RSI, MACD, ADX, Supertrend from Indicators::Calculator
    def ind_score(series)
      return 0 unless series&.candles&.any?

      score = 0.0
      calculator = Indicators::Calculator.new(series)

      # 1. RSI (0-2 points)
      rsi = numeric(calculator.rsi(14))
      if rsi
        if rsi > 50 && rsi < 70
          score += 2.0 # Strong bullish RSI
        elsif rsi > 40 && rsi < 80
          score += 1.0 # Moderate bullish RSI
        elsif rsi > 30
          score += 0.5 # Weak bullish RSI
        end
      end

      # 2. MACD (0-2 points)
      macd_result = calculator.macd(12, 26, 9)
      if macd_result.is_a?(Array) && macd_result.size >= 3
        macd_line = numeric(macd_result[0])
        signal = numeric(macd_result[1])
        histogram = numeric(macd_result[2])
        if macd_line && signal && histogram
          if macd_line > signal && histogram.positive?
            score += 2.0 # Strong bullish MACD
          elsif macd_line > signal
            score += 1.0 # Bullish MACD crossover
          elsif histogram.positive?
            score += 0.5 # Positive histogram
          end
        end
      end

      # 3. ADX (0-2 points)
      adx = numeric(calculator.adx(14))
      if adx
        if adx > 25
          score += 2.0 # Very strong trend
        elsif adx > 20
          score += 1.0 # Strong trend
        elsif adx > 15
          score += 0.5 # Moderate trend
        end
      end

      # 4. Supertrend (0-1 point)
      begin
        sanitized = sanitize_series(series) || series
        st_service = Indicators::Supertrend.new(series: sanitized, period: 10, base_multiplier: 2.0)
        st = st_service.call
        if st[:trend] == :bullish
          score += 1.0 # Bullish Supertrend
        end
      rescue StandardError => e
        Rails.logger.debug { "[TrendScorer] Supertrend calculation failed: #{e.message}" }
      end

      score.clamp(0.0, 7.0).round(1)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # Multi-timeframe score (0-7)
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # Uses: Primary TF vs Confirmation TF alignment
    def mtf_score(primary_series, confirmation_series)
      return 0 unless primary_series&.candles&.any?

      score = 0.0

      # If no confirmation timeframe, score based on primary only
      unless confirmation_series&.candles&.any?
        # Give partial score for having primary data
        return primary_series.candles.size >= 20 ? 3.5 : 1.5
      end

      primary_calculator = Indicators::Calculator.new(primary_series)
      confirmation_calculator = Indicators::Calculator.new(confirmation_series)

      # 1. RSI alignment (0-2 points)
      primary_rsi = numeric(primary_calculator.rsi(14))
      confirmation_rsi = numeric(confirmation_calculator.rsi(14))
      if primary_rsi && confirmation_rsi
        if primary_rsi > 50 && confirmation_rsi > 50
          score += 2.0 # Both bullish
        elsif (primary_rsi > 50) || (confirmation_rsi > 50)
          score += 1.0 # One bullish
        end
      end

      # 2. Trend alignment (0-3 points)
      primary_st = get_supertrend(primary_series)
      confirmation_st = get_supertrend(confirmation_series)
      if primary_st && confirmation_st
        if primary_st[:trend] == :bullish && confirmation_st[:trend] == :bullish
          score += 3.0 # Both bullish
        elsif primary_st[:trend] == :bullish || confirmation_st[:trend] == :bullish
          score += 1.5 # One bullish
        end
      end

      # 3. Price alignment (0-2 points)
      primary_closes = normalize_numeric_series(primary_series.closes)
      confirmation_closes = normalize_numeric_series(confirmation_series.closes)
      if primary_closes.size >= 6 && confirmation_closes.size >= 6
        primary_trend = primary_closes.last(3).sum / 3.0 > primary_closes[-6..-4].sum / 3.0
        confirmation_trend = confirmation_closes.last(3).sum / 3.0 > confirmation_closes[-6..-4].sum / 3.0
        if primary_trend && confirmation_trend
          score += 2.0 # Both trending up
        elsif primary_trend || confirmation_trend
          score += 1.0 # One trending up
        end
      end

      score.clamp(0.0, 7.0).round(1)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # Helper to get Supertrend safely
    def get_supertrend(series)
      return nil unless series

      sanitized = sanitize_series(series) || series
      st_service = Indicators::Supertrend.new(series: sanitized, period: 10, base_multiplier: 2.0)
      st_service.call
    rescue StandardError
      nil
    end

    def normalize_numeric_series(values)
      Array(values).filter_map { |val| numeric(val) }
    end

    def numeric(value)
      return nil if value.nil?
      return value.to_f if value.is_a?(Numeric)

      if value.is_a?(Hash)
        candidate = value[:value] || value['value'] || value[:close] || value['close']
        return candidate.to_f if candidate.respond_to?(:to_f)
      end
      if value.respond_to?(:to_f)
        float_value = value.to_f
        return float_value if float_value.finite?
      end
      nil
    rescue StandardError
      nil
    end

    def safe_swing_high?(series, index, lookback:)
      return false unless series.respond_to?(:swing_high?)

      series.swing_high?(index, lookback: lookback)
    rescue StandardError => e
      Rails.logger.debug { "[TrendScorer] swing_high? failed: #{e.message}" }
      false
    end

    def safe_swing_low?(series, index, lookback:)
      return false unless series.respond_to?(:swing_low?)

      series.swing_low?(index, lookback: lookback)
    rescue StandardError => e
      Rails.logger.debug { "[TrendScorer] swing_low? failed: #{e.message}" }
      false
    end

    def sanitize_series(series)
      return nil unless series

      highs = extract_series_component(series, :highs, :high)
      lows = extract_series_component(series, :lows, :low)
      closes = extract_series_component(series, :closes, :close)

      return nil if highs.empty? || lows.empty? || closes.empty?

      Struct.new(:highs, :lows, :closes).new(highs, lows, closes)
    end

    def extract_series_component(series, accessor, candle_attr)
      values =
        if series.respond_to?(accessor)
          series.public_send(accessor)
        elsif series.respond_to?(:candles)
          series.candles&.map do |candle|
            candle.respond_to?(candle_attr) ? candle.public_send(candle_attr) : candle[candle_attr] || candle[candle_attr.to_s]
          end
        else
          []
        end

      normalize_numeric_series(values)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
