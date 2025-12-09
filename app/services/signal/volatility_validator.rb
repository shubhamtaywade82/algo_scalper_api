# frozen_string_literal: true

module Signal
  # Validates volatility health before entry
  # Ensures market has sufficient volatility for profitable trades
  class VolatilityValidator
    Result = Struct.new(:valid, :atr_ratio, :factors, :reasons, keyword_init: true)

    # Validate volatility health
    # @param series [CandleSeries] Primary timeframe series
    # @param min_atr_ratio [Float] Minimum ATR ratio (default: 0.65)
    # @return [Result] Validation result with ATR ratio and factors
    def self.validate(series:, min_atr_ratio: 0.65)
      # Input validation
      return invalid_result('Series unavailable') unless series&.candles&.any?
      return invalid_result('Invalid min_atr_ratio (must be 0.0-2.0)') unless min_atr_ratio.between?(0.0, 2.0)

      factors = {}
      reasons = []

      # 1. ATR Ratio Check
      atr_factor = check_atr_ratio(series: series, min_ratio: min_atr_ratio)
      factors[:atr_ratio] = atr_factor
      valid = atr_factor[:valid]

      # 2. Compression Check
      compression_factor = check_compression(series: series)
      factors[:compression] = compression_factor
      valid = false if compression_factor[:in_compression]

      # 3. Lunchtime Chop Check
      chop_factor = check_lunchtime_chop(series: series)
      factors[:lunchtime_chop] = chop_factor
      valid = false if chop_factor[:in_chop]

      unless valid
        reasons << 'Volatility health check failed'
        reasons.concat(factors.values.select { |f| !f[:valid] && !f[:in_compression] && !f[:in_chop] }.map { |f| f[:reason] })
        reasons.concat(factors.values.select { |f| f[:in_compression] }.map { |f| f[:reason] })
        reasons.concat(factors.values.select { |f| f[:in_chop] }.map { |f| f[:reason] })
      end

      Result.new(
        valid: valid,
        atr_ratio: atr_factor[:ratio],
        factors: factors,
        reasons: reasons
      )
    rescue StandardError => e
      Rails.logger.error("[VolatilityValidator] Validation error: #{e.class} - #{e.message}")
      invalid_result("Validation error: #{e.message}")
    end

    private

    def self.check_atr_ratio(series:, min_ratio:)
      bars = series.candles
      return { valid: false, ratio: nil, reason: 'Insufficient candles' } if bars.size < 42

      # Calculate current ATR (last 14 bars)
      current_window = bars.last(14)
      current_atr = Entries::ATRUtils.calculate_atr(current_window)

      # Calculate historical ATR (non-overlapping: bars 15-28, previous period)
      historical_window = bars.last(42).first(14)  # Bars 15-28 (older period)
      historical_atr = Entries::ATRUtils.calculate_atr(historical_window)

      return { valid: false, ratio: nil, reason: 'ATR calculation failed' } unless current_atr && historical_atr&.positive?

      ratio = current_atr / historical_atr

      if ratio >= min_ratio
        { valid: true, ratio: ratio, reason: "ATR ratio #{ratio.round(2)} >= #{min_ratio}" }
      else
        { valid: false, ratio: ratio, reason: "ATR ratio #{ratio.round(2)} < #{min_ratio} (volatility too low)" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[VolatilityValidator] ATR ratio check failed: #{e.message}" }
      { valid: false, ratio: nil, reason: "ATR ratio check error: #{e.message}" }
    end

    def self.check_compression(series:)
      bars = series.candles
      return { in_compression: false, reason: 'Insufficient candles' } if bars.size < 20

      # Check if ATR is declining for 4+ consecutive periods (more sustained compression)
      atr_downtrend = Entries::ATRUtils.atr_downtrend?(bars, period: 14, min_downtrend_bars: 4)

      if atr_downtrend
        { in_compression: true, reason: 'ATR declining (volatility compression detected)' }
      else
        { in_compression: false, reason: 'No compression detected' }
      end
    rescue StandardError => e
      Rails.logger.debug { "[VolatilityValidator] Compression check failed: #{e.message}" }
      { in_compression: false, reason: "Compression check error: #{e.message}" }
    end

    def self.check_lunchtime_chop(series:)
      bars = series.candles
      return { in_chop: false, reason: 'Insufficient candles' } if bars.empty?

      last_candle = bars.last
      return { in_chop: false, reason: 'Timestamp unavailable' } unless last_candle.timestamp

      # Check if current time is in lunchtime window (11:20 - 13:30 IST)
      ist_time = last_candle.timestamp.in_time_zone('Asia/Kolkata')
      hour = ist_time.hour
      minute = ist_time.min

      in_lunch_window = (hour == 11 && minute >= 20) || (hour == 12) || (hour == 13 && minute <= 30)

      return { in_chop: false, reason: 'Not in lunchtime window' } unless in_lunch_window

      # Check for VWAP chop during lunchtime
      vwap_chop = Entries::VWAPUtils.vwap_chop?(bars.last(10), threshold_pct: 0.08, min_candles: 2)

      if vwap_chop
        { in_chop: true, reason: 'Lunchtime VWAP chop detected' }
      else
        { in_chop: false, reason: 'No lunchtime chop detected' }
      end
    rescue StandardError => e
      Rails.logger.debug { "[VolatilityValidator] Lunchtime chop check failed: #{e.message}" }
      { in_chop: false, reason: "Lunchtime chop check error: #{e.message}" }
    end

    def self.invalid_result(reason)
      Result.new(
        valid: false,
        atr_ratio: nil,
        factors: {},
        reasons: [reason]
      )
    end
  end
end
