# frozen_string_literal: true

module Signal
  class Engine
    class << self
      def run_for(index_cfg)
        Rails.logger.info("[Signal] Starting analysis for #{index_cfg[:key]} (#{index_cfg[:segment]})")

        timeframe = AlgoConfig.fetch.dig(:signals, :timeframe)
        Rails.logger.debug("[Signal] Using timeframe: #{timeframe}")

        # Calculate trading dates using Market::Calendar
        # from_date: 4-5 trading days ago for sufficient historical data
        # to_date: today or last trading day
        to_date = Market::Calendar.today_or_last_trading_day.strftime("%Y-%m-%d")
        from_date = Market::Calendar.trading_days_ago(5).strftime("%Y-%m-%d")
        Rails.logger.debug("[Signal] Fetching data from #{from_date} to #{to_date}")

        candles = DhanHQ::Models::HistoricalData.intraday(
          exchange_segment: index_cfg[:segment],
          security_id: index_cfg[:sid],
          instrument: "INDEX",
          interval: timeframe.gsub("m", ""), # Convert "5m" to "5"
          from_date: from_date,
          to_date: to_date
        )

        if candles.blank?
          Rails.logger.warn("[Signal] No candle data available for #{index_cfg[:key]}")
          return
        end

        Rails.logger.info("[Signal] Fetched #{candles.size} candles for #{index_cfg[:key]}")

        supertrend_cfg = AlgoConfig.fetch.dig(:signals, :supertrend)
        unless supertrend_cfg
          Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
          return
        end

        Rails.logger.debug("[Signal] Supertrend config: #{supertrend_cfg}")

        # Convert candles to CandleSeries format expected by Supertrend
        series = CandleSeries.new(symbol: index_cfg[:key], interval: timeframe.gsub("m", ""))
        series.load_from_raw(candles)

        st = Indicators::Supertrend.new(series: series, **supertrend_cfg).call
        Rails.logger.info("[Signal] Supertrend result for #{index_cfg[:key]}: trend=#{st[:trend]}, last_value=#{st[:last_value]}")

        adx_calculator = Indicators::Calculator.new(series)
        adx_value = adx_calculator.adx
        adx = { value: adx_value }
        Rails.logger.info("[Signal] ADX value for #{index_cfg[:key]}: #{adx_value}")

        direction = decide_direction(st, adx)
        Rails.logger.info("[Signal] Direction decision for #{index_cfg[:key]}: #{direction}")

        if direction == :avoid
          Rails.logger.info("[Signal] Avoiding trade for #{index_cfg[:key]} - conditions not met")
          return
        end

        # Comprehensive validation checks
        validation_result = comprehensive_validation(index_cfg, direction, candles, st, adx)
        unless validation_result[:valid]
          Rails.logger.warn("[Signal] Comprehensive validation failed for #{index_cfg[:key]}: #{validation_result[:reason]}")
          return
        end

        Rails.logger.info("[Signal] Proceeding with #{direction} signal for #{index_cfg[:key]}")

        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: direction)

        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{direction}")
          return
        end

        Rails.logger.info("[Signal] Found #{picks.size} option picks for #{index_cfg[:key]}: #{picks.map { |p| "#{p[:symbol]}@#{p[:strike]}" }.join(', ')}")

        picks.each_with_index do |pick, index|
          Rails.logger.info("[Signal] Attempting entry #{index + 1}/#{picks.size} for #{index_cfg[:key]}: #{pick[:symbol]}")
          result = Entries::EntryGuard.try_enter(index_cfg: index_cfg, pick: pick, direction: direction)

          if result
            Rails.logger.info("[Signal] Entry successful for #{index_cfg[:key]}: #{pick[:symbol]}")
          else
            Rails.logger.warn("[Signal] Entry failed for #{index_cfg[:key]}: #{pick[:symbol]}")
          end
        end

        Rails.logger.info("[Signal] Completed analysis for #{index_cfg[:key]}")
      rescue StandardError => e
        Rails.logger.error("[Signal] #{index_cfg[:key]} #{e.class} #{e.message}")
        Rails.logger.error("[Signal] Backtrace: #{e.backtrace.first(5).join(', ')}")
      end

      # Comprehensive validation checks before proceeding with trades
      def comprehensive_validation(index_cfg, direction, candles, supertrend_result, adx)
        Rails.logger.info("[Signal] Running comprehensive validation for #{index_cfg[:key]} #{direction}")

        validation_checks = []

        # 1. IV Rank Check - Avoid extreme volatility
        iv_rank_result = validate_iv_rank(index_cfg, candles)
        validation_checks << iv_rank_result

        # 2. Theta Risk Assessment - Avoid high theta decay
        theta_risk_result = validate_theta_risk(index_cfg, direction)
        validation_checks << theta_risk_result

        # 3. Enhanced ADX Confirmation - Ensure strong trend
        adx_result = validate_adx_strength(adx, supertrend_result)
        validation_checks << adx_result

        # 4. Trend Confirmation - Multiple signal validation
        trend_result = validate_trend_confirmation(supertrend_result, candles)
        validation_checks << trend_result

        # 5. Market Timing Check - Avoid problematic times
        timing_result = validate_market_timing
        validation_checks << timing_result

        # Log all validation results
        Rails.logger.info("[Signal] Validation Results:")
        validation_checks.each do |check|
          status = check[:valid] ? "✅" : "❌"
          Rails.logger.info("  #{status} #{check[:name]}: #{check[:message]}")
        end

        # Determine overall validation result
        failed_checks = validation_checks.select { |check| !check[:valid] }

        if failed_checks.empty?
          Rails.logger.info("[Signal] All validation checks passed for #{index_cfg[:key]}")
          { valid: true, reason: "All checks passed" }
        else
          failed_reasons = failed_checks.map { |check| check[:name] }.join(", ")
          { valid: false, reason: "Failed checks: #{failed_reasons}" }
        end
      end

      # Validate IV Rank - avoid extreme volatility conditions
      def validate_iv_rank(index_cfg, candles)
        # For now, we'll use a simple volatility check based on recent price movement
        # In a full implementation, you'd calculate actual IV rank from historical IV data

        if candles.size < 5
          return { valid: false, name: "IV Rank", message: "Insufficient data for volatility assessment" }
        end

        # Calculate recent volatility as a proxy for IV rank
        recent_candles = candles.last(5)
        price_changes = recent_candles.each_cons(2).map { |c1, c2| (c2[:close] - c1[:close]).abs / c1[:close] }
        avg_volatility = price_changes.sum / price_changes.size

        # Normalize volatility (this is a simplified approach)
        iv_rank_proxy = [ (avg_volatility * 1000), 1.0 ].min  # Cap at 1.0

        if iv_rank_proxy > 0.8
          { valid: false, name: "IV Rank", message: "Extreme volatility detected (#{(iv_rank_proxy * 100).round(1)}%)" }
        elsif iv_rank_proxy < 0.1
          { valid: false, name: "IV Rank", message: "Very low volatility (#{(iv_rank_proxy * 100).round(1)}%)" }
        else
          { valid: true, name: "IV Rank", message: "Volatility within acceptable range (#{(iv_rank_proxy * 100).round(1)}%)" }
        end
      end

      # Validate theta risk - avoid high theta decay situations
      def validate_theta_risk(index_cfg, direction)
        current_time = Time.zone.now
        hour = current_time.hour
        minute = current_time.min

        # High theta risk periods (last hour of trading)
        if hour >= 14 && minute >= 30  # After 2:30 PM
          { valid: false, name: "Theta Risk", message: "High theta decay risk - too close to market close" }
        elsif hour >= 14  # After 2:00 PM
          { valid: true, name: "Theta Risk", message: "Moderate theta risk - afternoon trading" }
        else
          { valid: true, name: "Theta Risk", message: "Low theta risk - early/midday trading" }
        end
      end

      # Enhanced ADX validation with trend strength assessment
      def validate_adx_strength(adx, supertrend_result)
        adx_value = adx[:value].to_f
        min_strength = AlgoConfig.fetch.dig(:signals, :adx, :min_strength).to_f

        if adx_value < min_strength
          { valid: false, name: "ADX Strength", message: "Weak trend strength (#{adx_value.round(1)} < #{min_strength})" }
        elsif adx_value >= 40
          { valid: true, name: "ADX Strength", message: "Very strong trend (#{adx_value.round(1)})" }
        elsif adx_value >= 25
          { valid: true, name: "ADX Strength", message: "Strong trend (#{adx_value.round(1)})" }
        else
          { valid: true, name: "ADX Strength", message: "Moderate trend (#{adx_value.round(1)})" }
        end
      end

      # Validate trend confirmation with multiple signals
      def validate_trend_confirmation(supertrend_result, candles)
        trend = supertrend_result[:trend]

        if trend.nil?
          return { valid: false, name: "Trend Confirmation", message: "No trend signal from Supertrend" }
        end

        # Additional confirmation: check if recent price action supports the trend
        if candles.size < 3
          return { valid: false, name: "Trend Confirmation", message: "Insufficient data for trend confirmation" }
        end

        recent_candles = candles.last(3)

        # Check if recent closes are moving in trend direction
        case trend
        when :bullish
          if recent_candles.last[:close] > recent_candles.first[:close]
            { valid: true, name: "Trend Confirmation", message: "Bullish trend confirmed by price action" }
          else
            { valid: false, name: "Trend Confirmation", message: "Bullish signal not confirmed by recent price action" }
          end
        when :bearish
          if recent_candles.last[:close] < recent_candles.first[:close]
            { valid: true, name: "Trend Confirmation", message: "Bearish trend confirmed by price action" }
          else
            { valid: false, name: "Trend Confirmation", message: "Bearish signal not confirmed by recent price action" }
          end
        else
          { valid: false, name: "Trend Confirmation", message: "Unknown trend direction" }
        end
      end

      # Validate market timing - avoid problematic trading times
      def validate_market_timing
        current_time = Time.zone.now
        hour = current_time.hour
        minute = current_time.min

        # Market hours: 9:15 AM to 3:30 PM IST
        market_open = hour >= 9 && (hour > 9 || minute >= 15)
        market_close = hour >= 15 && minute >= 30

        if !market_open
          { valid: false, name: "Market Timing", message: "Market not yet open" }
        elsif market_close
          { valid: false, name: "Market Timing", message: "Market closed" }
        elsif hour == 9 && minute < 30
          { valid: true, name: "Market Timing", message: "Early market - high volatility period" }
        elsif hour >= 14 && minute >= 30
          { valid: true, name: "Market Timing", message: "Late market - theta decay risk" }
        else
          { valid: true, name: "Market Timing", message: "Normal trading hours" }
        end
      end

      def decide_direction(supertrend_result, adx)
        min_strength = AlgoConfig.fetch.dig(:signals, :adx, :min_strength).to_f
        adx_value = adx[:value].to_f

        Rails.logger.debug("[Signal] ADX check: value=#{adx_value}, min_required=#{min_strength}")

        if adx_value < min_strength
          Rails.logger.info("[Signal] ADX too weak: #{adx_value} < #{min_strength}")
          return :avoid
        end

        if supertrend_result.blank? || supertrend_result[:trend].nil?
          Rails.logger.warn("[Signal] Supertrend result invalid: #{supertrend_result}")
          return :avoid
        end

        trend = supertrend_result[:trend]
        Rails.logger.debug("[Signal] Supertrend trend: #{trend}")

        # Use the trend from Supertrend calculation
        case trend
        when :bullish
          Rails.logger.info("[Signal] Bullish signal confirmed: ADX=#{adx_value}, Supertrend=#{trend}")
          :bullish
        when :bearish
          Rails.logger.info("[Signal] Bearish signal confirmed: ADX=#{adx_value}, Supertrend=#{trend}")
          :bearish
        else
          Rails.logger.info("[Signal] Neutral/unknown trend: #{trend}")
          :avoid
        end
      end
    end
  end
end
