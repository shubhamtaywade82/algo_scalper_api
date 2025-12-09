# frozen_string_literal: true

module Signal
  # Validates momentum before entry
  # Requires at least 1 momentum confirmation
  class MomentumValidator
    Result = Struct.new(:valid, :score, :factors, :reasons, keyword_init: true)

    # Validate momentum with multiple checks
    # @param instrument [Instrument] Instrument object
    # @param series [CandleSeries] Primary timeframe series
    # @param direction [Symbol] Trade direction (:bullish or :bearish)
    # @param min_confirmations [Integer] Minimum confirmations required (default: 1)
    # @return [Result] Validation result with score and factors
    def self.validate(instrument:, series:, direction:, min_confirmations: 1)
      return invalid_result('Missing required parameters') unless instrument && series

      factors = {}
      score = 0
      reasons = []

      # 1. LTP > Last Swing (for bullish) or LTP < Last Swing (for bearish)
      swing_factor = check_ltp_vs_swing(instrument: instrument, series: series, direction: direction)
      factors[:ltp_swing] = swing_factor
      score += 1 if swing_factor[:confirms]

      # 2. Candle Body Expansion
      body_factor = check_body_expansion(series: series, direction: direction)
      factors[:body_expansion] = body_factor
      score += 1 if body_factor[:confirms]

      # 3. Option Premium Speed (if trading options)
      premium_factor = check_premium_speed(instrument: instrument, series: series, direction: direction)
      factors[:premium_speed] = premium_factor
      score += 1 if premium_factor[:confirms]

      # Volume expansion check skipped (volume always 0 for indices)

      valid = score >= min_confirmations

      unless valid
        reasons << "Insufficient momentum confirmation: #{score}/3 checks confirm (minimum: #{min_confirmations})"
        reasons.concat(factors.values.select { |f| !f[:confirms] }.map { |f| f[:reason] })
      end

      Result.new(
        valid: valid,
        score: score,
        factors: factors,
        reasons: reasons
      )
    rescue StandardError => e
      Rails.logger.error("[MomentumValidator] Validation error: #{e.class} - #{e.message}")
      invalid_result("Validation error: #{e.message}")
    end

    private

    def self.check_ltp_vs_swing(instrument:, series:, direction:)
      return { confirms: false, reason: 'Series unavailable' } unless series&.candles&.any?

      bars = series.candles.last(20)
      return { confirms: false, reason: 'Insufficient candles' } if bars.size < 5

      # Get current LTP
      current_price = bars.last.close
      return { confirms: false, reason: 'Current price unavailable' } unless current_price&.positive?

      # Find last swing high/low
      case direction
      when :bullish
        # For bullish, check if LTP > last swing high
        swing_highs = []
        (bars.size - 5..bars.size - 2).each do |i|
          next if i < 0 || i >= bars.size

          bar = bars[i]
          # Check if this is a swing high (higher than neighbors)
          if i > 0 && i < bars.size - 1
            prev_high = bars[i - 1].high
            next_high = bars[i + 1].high
            swing_highs << bar.high if bar.high > prev_high && bar.high > next_high
          end
        end

        last_swing_high = swing_highs.max
        if last_swing_high && current_price > last_swing_high
          { confirms: true, reason: "LTP #{current_price.round(2)} > swing high #{last_swing_high.round(2)}" }
        else
          { confirms: false, reason: "LTP #{current_price.round(2)} not above swing high" }
        end
      when :bearish
        # For bearish, check if LTP < last swing low
        swing_lows = []
        (bars.size - 5..bars.size - 2).each do |i|
          next if i < 0 || i >= bars.size

          bar = bars[i]
          # Check if this is a swing low (lower than neighbors)
          if i > 0 && i < bars.size - 1
            prev_low = bars[i - 1].low
            next_low = bars[i + 1].low
            swing_lows << bar.low if bar.low < prev_low && bar.low < next_low
          end
        end

        last_swing_low = swing_lows.min
        if last_swing_low && current_price < last_swing_low
          { confirms: true, reason: "LTP #{current_price.round(2)} < swing low #{last_swing_low.round(2)}" }
        else
          { confirms: false, reason: "LTP #{current_price.round(2)} not below swing low" }
        end
      else
        { confirms: false, reason: "Invalid direction: #{direction}" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[MomentumValidator] LTP swing check failed: #{e.message}" }
      { confirms: false, reason: "LTP swing check error: #{e.message}" }
    end

    def self.check_body_expansion(series:, direction:)
      return { confirms: false, reason: 'Series unavailable' } unless series&.candles&.any?

      bars = series.candles.last(5)
      return { confirms: false, reason: 'Insufficient candles' } if bars.size < 4

      last_candle = bars.last
      prev_candles = bars[0..-2]

      # Calculate average body size of previous candles
      prev_body_sizes = prev_candles.map { |c| (c.close - c.open).abs }
      avg_body_size = prev_body_sizes.sum.to_f / prev_body_sizes.size

      return { confirms: false, reason: 'Average body size is zero' } if avg_body_size.zero?

      current_body_size = (last_candle.close - last_candle.open).abs
      expansion_ratio = current_body_size / avg_body_size

      # Require at least 1.2x expansion (20% larger)
      if expansion_ratio >= 1.2
        case direction
        when :bullish
          if last_candle.bullish?
            { confirms: true, reason: "Body expansion #{expansion_ratio.round(2)}x (bullish)" }
          else
            { confirms: false, reason: "Body expansion but candle is bearish" }
          end
        when :bearish
          if last_candle.bearish?
            { confirms: true, reason: "Body expansion #{expansion_ratio.round(2)}x (bearish)" }
          else
            { confirms: false, reason: "Body expansion but candle is bullish" }
          end
        else
          { confirms: false, reason: "Invalid direction: #{direction}" }
        end
      else
        { confirms: false, reason: "Body expansion #{expansion_ratio.round(2)}x < 1.2x threshold" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[MomentumValidator] Body expansion check failed: #{e.message}" }
      { confirms: false, reason: "Body expansion check error: #{e.message}" }
    end

    def self.check_premium_speed(instrument:, series:, direction:)
      # Option premium speed: Check if LTP is moving fast (ΔLTP > threshold)
      return { confirms: false, reason: 'Series unavailable' } unless series&.candles&.any?

      bars = series.candles.last(3)
      return { confirms: false, reason: 'Insufficient candles' } if bars.size < 2

      # Calculate price change percentage over last 2 candles
      prev_close = bars[-2].close
      current_close = bars.last.close

      return { confirms: false, reason: 'Price data unavailable' } unless prev_close&.positive?

      price_change_pct = ((current_close - prev_close) / prev_close * 100).abs

      # Require at least 0.3% move in 1-2 candles (momentum)
      threshold_pct = 0.3

      if price_change_pct >= threshold_pct
        case direction
        when :bullish
          if current_close > prev_close
            { confirms: true, reason: "Premium speed #{price_change_pct.round(2)}% (bullish)" }
          else
            { confirms: false, reason: "Price moving down despite bullish direction" }
          end
        when :bearish
          if current_close < prev_close
            { confirms: true, reason: "Premium speed #{price_change_pct.round(2)}% (bearish)" }
          else
            { confirms: false, reason: "Price moving up despite bearish direction" }
          end
        else
          { confirms: false, reason: "Invalid direction: #{direction}" }
        end
      else
        { confirms: false, reason: "Premium speed #{price_change_pct.round(2)}% < #{threshold_pct}% threshold" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[MomentumValidator] Premium speed check failed: #{e.message}" }
      { confirms: false, reason: "Premium speed check error: #{e.message}" }
    end

    def self.invalid_result(reason)
      Result.new(
        valid: false,
        score: 0,
        factors: {},
        reasons: [reason]
      )
    end
  end
end
