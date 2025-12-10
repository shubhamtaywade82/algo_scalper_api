# frozen_string_literal: true

module Signal
  # Validates trade direction using multi-factor confirmation
  # Requires at least 2 factors to agree for direction validation
  class DirectionValidator
    Result = Struct.new(:valid, :direction, :score, :factors, :reasons, keyword_init: true)

    # Validate direction with multi-factor confirmation
    # @param index_cfg [Hash] Index configuration
    # @param instrument [Instrument] Instrument object
    # @param primary_series [CandleSeries] Primary timeframe series
    # @param primary_supertrend [Hash] Primary timeframe Supertrend result
    # @param primary_adx [Float] Primary timeframe ADX value
    # @param min_agreement [Integer] Minimum factors that must agree (default: 2)
    # @return [Result] Validation result with direction, score, and factors
    def self.validate(index_cfg:, instrument:, primary_series:, primary_supertrend:,
                     primary_adx:, min_agreement: 2)
      # Input validation
      return invalid_result('Missing instrument') unless instrument
      return invalid_result('Missing primary_series') unless primary_series
      return invalid_result('Invalid primary_supertrend') unless primary_supertrend.is_a?(Hash)
      return invalid_result('Invalid primary_adx') unless primary_adx.is_a?(Numeric)
      return invalid_result('Invalid min_agreement (must be 1-6)') unless min_agreement.between?(1, 6)

      factors = {}
      score = 0
      reasons = []

      # 1. HTF Supertrend (15m or 30m) with ADX strength check
      htf_factor = check_htf_supertrend(
        instrument: instrument,
        index_cfg: index_cfg,
        primary_supertrend: primary_supertrend
      )
      factors[:htf_supertrend] = htf_factor
      score += 1 if htf_factor[:agrees]

      # 2. ADX Strength
      adx_factor = check_adx_strength(adx: primary_adx, index_cfg: index_cfg)
      factors[:adx] = adx_factor
      score += 1 if adx_factor[:agrees]

      # 3. VWAP Position
      vwap_factor = check_vwap_position(series: primary_series, direction: primary_supertrend[:trend])
      factors[:vwap] = vwap_factor
      score += 1 if vwap_factor[:agrees]

      # 4. BOS Direction Alignment
      bos_factor = check_bos_alignment(series: primary_series, direction: primary_supertrend[:trend])
      factors[:bos] = bos_factor
      score += 1 if bos_factor[:agrees]

      # 5. SMC CHOCH Alignment
      choch_factor = check_choch_alignment(series: primary_series, direction: primary_supertrend[:trend])
      factors[:choch] = choch_factor
      score += 1 if choch_factor[:agrees]

      # 6. 5m Candle Structure
      structure_factor = check_candle_structure(series: primary_series, direction: primary_supertrend[:trend])
      factors[:structure] = structure_factor
      score += 1 if structure_factor[:agrees]

      # Determine final direction
      direction = primary_supertrend[:trend]
      valid = score >= min_agreement && direction.in?([:bullish, :bearish])

      unless valid
        reasons << "Insufficient directional agreement: #{score}/6 factors agree (minimum: #{min_agreement})"
        reasons.concat(factors.values.select { |f| !f[:agrees] }.map { |f| f[:reason] })
      end

      Result.new(
        valid: valid,
        direction: valid ? direction : :avoid,
        score: score,
        factors: factors,
        reasons: reasons
      )
    rescue StandardError => e
      Rails.logger.error("[DirectionValidator] Validation error: #{e.class} - #{e.message}")
      invalid_result("Validation error: #{e.message}")
    end

    private

    def self.check_htf_supertrend(instrument:, index_cfg:, primary_supertrend:)
      # Check 15m Supertrend as HTF confirmation (reuse primary_supertrend to avoid recalculation)
      htf_series = instrument.candle_series(interval: '15')
      return { agrees: false, reason: 'HTF data unavailable' } unless htf_series&.candles&.any?

      signals_cfg = AlgoConfig.fetch[:signals] || {}
      supertrend_cfg = signals_cfg[:supertrend] || { period: 7, multiplier: 3.0 }

      st_service = Indicators::Supertrend.new(series: htf_series, **supertrend_cfg)
      htf_st = st_service.call

      # Validate HTF trend strength with ADX
      htf_adx = instrument.adx(14, interval: '15')
      index_key = index_cfg[:key].to_s.upcase
      # AGGRESSIVE: Very low HTF ADX thresholds (5-8) for aggressive entries
      adx_thresholds = {
        'NIFTY' => 5,
        'BANKNIFTY' => 6,
        'SENSEX' => 5
      }
      min_htf_adx = adx_thresholds[index_key] || 5

      # Check alignment AND strength
      if htf_st[:trend] == primary_supertrend[:trend] &&
         htf_st[:trend].in?([:bullish, :bearish]) &&
         htf_adx && htf_adx >= min_htf_adx
        { agrees: true, reason: "HTF Supertrend (#{htf_st[:trend]}) aligns with ADX #{htf_adx.round(1)}" }
      elsif htf_st[:trend] != primary_supertrend[:trend]
        { agrees: false, reason: "HTF Supertrend (#{htf_st[:trend]}) does not align with primary" }
      elsif htf_adx.nil? || htf_adx < min_htf_adx
        { agrees: false, reason: "HTF ADX #{htf_adx&.round(1)} < #{min_htf_adx} (weak trend)" }
      else
        { agrees: false, reason: "HTF Supertrend (#{htf_st[:trend]}) validation failed" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[DirectionValidator] HTF check failed: #{e.message}" }
      { agrees: false, reason: "HTF check error: #{e.message}" }
    end

    def self.check_adx_strength(adx:, index_cfg:)
      adx_value = adx.to_f
      index_key = index_cfg[:key].to_s.upcase

      # AGGRESSIVE: Very low ADX thresholds (5-8) for aggressive entries
      thresholds = {
        'NIFTY' => 5,
        'BANKNIFTY' => 6,
        'SENSEX' => 5
      }
      min_adx = thresholds[index_key] || 5

      if adx_value >= min_adx
        { agrees: true, reason: "ADX #{adx_value.round(1)} >= #{min_adx}" }
      else
        { agrees: false, reason: "ADX #{adx_value.round(1)} < #{min_adx}" }
      end
    end

    def self.check_vwap_position(series:, direction:)
      return { agrees: false, reason: 'Series unavailable' } unless series&.candles&.any?

      bars = series.candles.last(20) # Use last 20 candles for VWAP
      return { agrees: false, reason: 'Insufficient candles' } if bars.size < 10

      vwap = Entries::VWAPUtils.calculate_vwap(bars)
      return { agrees: false, reason: 'VWAP calculation failed' } unless vwap&.positive?

      current_price = bars.last.close
      return { agrees: false, reason: 'Current price unavailable' } unless current_price&.positive?

      case direction
      when :bullish
        if current_price > vwap
          { agrees: true, reason: "Price above VWAP (#{current_price.round(2)} > #{vwap.round(2)})" }
        else
          { agrees: false, reason: "Price below VWAP (#{current_price.round(2)} < #{vwap.round(2)})" }
        end
      when :bearish
        if current_price < vwap
          { agrees: true, reason: "Price below VWAP (#{current_price.round(2)} < #{vwap.round(2)})" }
        else
          { agrees: false, reason: "Price above VWAP (#{current_price.round(2)} > #{vwap.round(2)})" }
        end
      else
        { agrees: false, reason: "Invalid direction: #{direction}" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[DirectionValidator] VWAP check failed: #{e.message}" }
      { agrees: false, reason: "VWAP check error: #{e.message}" }
    end

    def self.check_bos_alignment(series:, direction:)
      return { agrees: false, reason: 'Series unavailable' } unless series&.candles&.any?

      bars = series.candles
      bos_dir = Entries::StructureDetector.bos_direction(bars, lookback_minutes: 10)

      if bos_dir == direction
        { agrees: true, reason: "BOS direction (#{bos_dir}) aligns" }
      elsif bos_dir == :neutral
        { agrees: false, reason: 'No BOS detected' }
      else
        { agrees: false, reason: "BOS direction (#{bos_dir}) does not align" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[DirectionValidator] BOS check failed: #{e.message}" }
      { agrees: false, reason: "BOS check error: #{e.message}" }
    end

    def self.check_choch_alignment(series:, direction:)
      return { agrees: false, reason: 'Series unavailable' } unless series&.candles&.any?

      bars = series.candles
      choch_dir = Entries::StructureDetector.choch?(bars, lookback_minutes: 15)

      if choch_dir == direction
        { agrees: true, reason: "CHOCH direction (#{choch_dir}) aligns" }
      elsif choch_dir == :neutral
        { agrees: false, reason: 'No CHOCH detected' }
      else
        { agrees: false, reason: "CHOCH direction (#{choch_dir}) does not align" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[DirectionValidator] CHOCH check failed: #{e.message}" }
      { agrees: false, reason: "CHOCH check error: #{e.message}" }
    end

    def self.check_candle_structure(series:, direction:)
      return { agrees: false, reason: 'Series unavailable' } unless series&.candles&.any?

      bars = series.candles.last(5)
      return { agrees: false, reason: 'Insufficient candles' } if bars.size < 3

      case direction
      when :bullish
        # Check for higher highs pattern (strict: b > a, not b >= a)
        highs = bars.map(&:high)
        # Require at least 80% of pairs to show strict higher highs
        higher_highs_count = highs.each_cons(2).count { |a, b| b > a }
        higher_highs_ratio = higher_highs_count.to_f / [highs.size - 1, 1].max
        if higher_highs_ratio >= 0.8
          { agrees: true, reason: "Higher highs pattern detected (#{(higher_highs_ratio * 100).round}%)" }
        else
          { agrees: false, reason: "No higher highs pattern (#{(higher_highs_ratio * 100).round}% < 80%)" }
        end
      when :bearish
        # Check for lower lows pattern (strict: b < a, not b <= a)
        lows = bars.map(&:low)
        # Require at least 80% of pairs to show strict lower lows
        lower_lows_count = lows.each_cons(2).count { |a, b| b < a }
        lower_lows_ratio = lower_lows_count.to_f / [lows.size - 1, 1].max
        if lower_lows_ratio >= 0.8
          { agrees: true, reason: "Lower lows pattern detected (#{(lower_lows_ratio * 100).round}%)" }
        else
          { agrees: false, reason: "No lower lows pattern (#{(lower_lows_ratio * 100).round}% < 80%)" }
        end
      else
        { agrees: false, reason: "Invalid direction: #{direction}" }
      end
    rescue StandardError => e
      Rails.logger.debug { "[DirectionValidator] Structure check failed: #{e.message}" }
      { agrees: false, reason: "Structure check error: #{e.message}" }
    end

    def self.invalid_result(reason)
      Result.new(
        valid: false,
        direction: :avoid,
        score: 0,
        factors: {},
        reasons: [reason]
      )
    end
  end
end
