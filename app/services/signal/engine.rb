# frozen_string_literal: true

module Signal
  class Engine
    class << self
      def run_for(index_cfg)
        Rails.logger.info("[Signal] Starting analysis for #{index_cfg[:key]} (#{index_cfg[:segment]})")

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, true)
        confirmation_tf = if enable_confirmation
                            signals_cfg[:confirmation_timeframe].presence&.to_s
                          else
                            nil
                          end

        Rails.logger.debug { "[Signal] Primary timeframe: #{primary_tf}, confirmation timeframe: #{confirmation_tf || 'none'} (enabled: #{enable_confirmation})" }

        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.error("[Signal] Could not find instrument for #{index_cfg[:key]}")
          return
        end

        supertrend_cfg = signals_cfg[:supertrend]
        unless supertrend_cfg
          Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
          return
        end

        adx_cfg = signals_cfg[:adx] || {}
        enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, true)
        # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
        adx_min_strength = enable_adx_filter ? adx_cfg[:min_strength] : 0

        primary_analysis = analyze_timeframe(
          index_cfg: index_cfg,
          instrument: instrument,
          timeframe: primary_tf,
          supertrend_cfg: supertrend_cfg,
          adx_min_strength: adx_min_strength
        )

        unless primary_analysis[:status] == :ok
          Rails.logger.warn("[Signal] Primary timeframe analysis unavailable for #{index_cfg[:key]}: #{primary_analysis[:message]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        final_direction = primary_analysis[:direction]
        confirmation_analysis = nil

        if confirmation_tf.present?
          mode_config = get_validation_mode_config
          # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
          confirmation_adx_min = if enable_adx_filter
                                   mode_config[:adx_confirmation_min_strength] || adx_cfg[:confirmation_min_strength] || adx_cfg[:min_strength]
                                 else
                                   0
                                 end

          confirmation_analysis = analyze_timeframe(
            index_cfg: index_cfg,
            instrument: instrument,
            timeframe: confirmation_tf,
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: confirmation_adx_min
          )

          unless confirmation_analysis[:status] == :ok
            Rails.logger.warn("[Signal] Confirmation timeframe analysis unavailable for #{index_cfg[:key]}: #{confirmation_analysis[:message]}")
            Signal::StateTracker.reset(index_cfg[:key])
            return
          end

          final_direction = multi_timeframe_direction(primary_analysis[:direction], confirmation_analysis[:direction])
          Rails.logger.info("[Signal] Multi-timeframe decision for #{index_cfg[:key]}: primary=#{primary_analysis[:direction]} confirmation=#{confirmation_analysis[:direction]} final=#{final_direction}")
        end

        if final_direction == :avoid
          Rails.logger.info("[Signal] Avoiding trade for #{index_cfg[:key]} - multi-timeframe bias mismatch or weak trend")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        primary_series = primary_analysis[:series]
        validation_result = comprehensive_validation(index_cfg, final_direction, primary_series,
                                                     primary_analysis[:supertrend], { value: primary_analysis[:adx_value] })
        unless validation_result[:valid]
          Rails.logger.warn("[Signal] Comprehensive validation failed for #{index_cfg[:key]}: #{validation_result[:reason]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        Rails.logger.info("[Signal] Proceeding with #{final_direction} signal for #{index_cfg[:key]}")

        # Get state snapshot first for signal persistence
        state_snapshot = Signal::StateTracker.record(
          index_key: index_cfg[:key],
          direction: final_direction,
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          config: signals_cfg
        )

        # Persist signal with confidence score
        confidence_score = calculate_confidence_score(
          primary_analysis: primary_analysis,
          confirmation_analysis: confirmation_analysis,
          validation_result: validation_result
        )

        TradingSignal.create_from_analysis(
          index_key: index_cfg[:key],
          direction: final_direction.to_s,
          timeframe: primary_tf,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: confidence_score,
          metadata: {
            confirmation_timeframe: confirmation_tf,
            confirmation_direction: confirmation_analysis&.dig(:direction),
            validation_passed: validation_result[:valid],
            state_count: state_snapshot[:count],
            state_multiplier: state_snapshot[:multiplier]
          }
        )

        Rails.logger.info("[Signal] Signal state for #{index_cfg[:key]}: count=#{state_snapshot[:count]} multiplier=#{state_snapshot[:multiplier]}")

        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: final_direction)

        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{final_direction}")
          return
        end

        Rails.logger.info("[Signal] Found #{picks.size} option picks for #{index_cfg[:key]}: #{picks.map { |p| "#{p[:symbol]}@#{p[:strike]}" }.join(', ')}")

        picks.each_with_index do |pick, index|
          Rails.logger.info("[Signal] Attempting entry #{index + 1}/#{picks.size} for #{index_cfg[:key]}: #{pick[:symbol]} (scale x#{state_snapshot[:multiplier]})")
          result = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: final_direction,
            scale_multiplier: state_snapshot[:multiplier]
          )

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

      def analyze_timeframe(index_cfg:, instrument:, timeframe:, supertrend_cfg:, adx_min_strength:)
        interval = normalize_interval(timeframe)
        if interval.blank?
          message = "Invalid timeframe '#{timeframe}'"
          Rails.logger.error("[Signal] #{message} for #{index_cfg[:key]}")
          return { status: :error, message: message }
        end

        series = instrument.candle_series(interval: interval)
        unless series&.candles&.any?
          message = "No candle data (#{timeframe})"
          Rails.logger.warn("[Signal] #{message} for #{index_cfg[:key]}")
          return { status: :no_data, message: message }
        end

        Rails.logger.info("[Signal] Fetched #{series.candles.size} candles for #{index_cfg[:key]} @ #{timeframe}")
        Rails.logger.debug { "[Signal] Adaptive Supertrend config: #{supertrend_cfg}" }

        st_service = Indicators::Supertrend.new(series: series, **supertrend_cfg)
        st = st_service.call
        last_multiplier = st[:adaptive_multipliers]&.compact&.last
        Rails.logger.info(
          "[Signal] Supertrend(#{timeframe}) for #{index_cfg[:key]}: trend=#{st[:trend]} last_value=#{st[:last_value]} multiplier=#{last_multiplier}"
        )

        adx_value = instrument.adx(14, interval: interval)
        Rails.logger.info("[Signal] ADX(#{timeframe}) for #{index_cfg[:key]}: #{adx_value}")

        direction = decide_direction(
          st,
          adx_value,
          min_strength: adx_min_strength,
          timeframe_label: timeframe
        )

        {
          status: :ok,
          series: series,
          supertrend: st,
          adx_value: adx_value,
          direction: direction,
          last_candle_timestamp: series.candles.last&.timestamp
        }
      rescue StandardError => e
        Rails.logger.error("[Signal] Timeframe analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      def analyze_multi_timeframe(index_cfg:, instrument:)
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, true)
        confirmation_tf = if enable_confirmation
                            signals_cfg[:confirmation_timeframe].presence&.to_s
                          else
                            nil
                          end

        supertrend_cfg = signals_cfg[:supertrend]
        unless supertrend_cfg
          Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
          return { status: :error, message: 'Supertrend configuration missing' }
        end

        adx_cfg = signals_cfg[:adx] || {}
        enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, true)
        # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
        adx_min_strength = enable_adx_filter ? adx_cfg[:min_strength] : 0

        # Analyze primary timeframe
        primary_analysis = analyze_timeframe(
          index_cfg: index_cfg,
          instrument: instrument,
          timeframe: primary_tf,
          supertrend_cfg: supertrend_cfg,
          adx_min_strength: adx_min_strength
        )

        unless primary_analysis[:status] == :ok
          return { status: :error, message: "Primary timeframe analysis failed: #{primary_analysis[:message]}" }
        end

        primary_direction = primary_analysis[:direction]
        confirmation_analysis = nil
        confirmation_direction = nil

        if confirmation_tf.present?
          # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
          confirmation_adx_min = if enable_adx_filter
                                   adx_cfg[:confirmation_min_strength] || adx_cfg[:min_strength]
                                 else
                                   0
                                 end

          confirmation_analysis = analyze_timeframe(
            index_cfg: index_cfg,
            instrument: instrument,
            timeframe: confirmation_tf,
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: confirmation_adx_min
          )

          confirmation_direction = confirmation_analysis[:direction] if confirmation_analysis[:status] == :ok
        end

        final_direction = multi_timeframe_direction(primary_direction, confirmation_direction)

        {
          status: :ok,
          primary_direction: primary_direction,
          confirmation_direction: confirmation_direction,
          final_direction: final_direction,
          timeframe_results: {
            primary: primary_analysis,
            confirmation: confirmation_analysis
          }
        }
      rescue StandardError => e
        Rails.logger.error("[Signal] Multi-timeframe analysis failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      def multi_timeframe_direction(primary_direction, confirmation_direction)
        # If no confirmation timeframe, use primary direction
        return primary_direction if confirmation_direction.nil?

        # If either is avoid, return avoid
        return :avoid if primary_direction == :avoid || confirmation_direction == :avoid

        # If both align, return that direction
        return primary_direction if primary_direction == confirmation_direction

        # Directions don't match
        :avoid
      end

      def normalize_interval(timeframe)
        return if timeframe.blank?

        cleaned = timeframe.to_s.strip.downcase
        digits = cleaned.gsub(/[^0-9]/, '')
        digits.presence
      end

      # Comprehensive validation checks before proceeding with trades
      def comprehensive_validation(index_cfg, direction, series, supertrend_result, adx)
        mode_config = get_validation_mode_config
        Rails.logger.info("[Signal] Running comprehensive validation for #{index_cfg[:key]} #{direction} (mode: #{mode_config[:mode]})")

        validation_checks = []

        # 1. IV Rank Check - Avoid extreme volatility (if enabled)
        if mode_config[:require_iv_rank_check]
          iv_rank_result = validate_iv_rank(index_cfg, series, mode_config)
          validation_checks << iv_rank_result
        end

        # 2. Theta Risk Assessment - Avoid high theta decay (if enabled)
        if mode_config[:require_theta_risk_check]
          theta_risk_result = validate_theta_risk(index_cfg, direction, mode_config)
          validation_checks << theta_risk_result
        end

        # 3. Enhanced ADX Confirmation - Ensure strong trend (if enabled)
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, true)
        if enable_adx_filter
          adx_result = validate_adx_strength(adx, supertrend_result, mode_config)
          validation_checks << adx_result
        else
          Rails.logger.debug('[Signal] ADX validation skipped (filter disabled)')
          validation_checks << { valid: true, name: 'ADX Strength', message: 'ADX filter disabled' }
        end

        # 4. Trend Confirmation - Multiple signal validation (if enabled)
        if mode_config[:require_trend_confirmation]
          trend_result = validate_trend_confirmation(supertrend_result, series)
          validation_checks << trend_result
        end

        # 5. Market Timing Check - Avoid problematic times (always required)
        timing_result = validate_market_timing
        validation_checks << timing_result

        # Log all validation results
        Rails.logger.info("[Signal] Validation Results (#{mode_config[:mode]} mode):")
        validation_checks.each do |check|
          status = check[:valid] ? '✅' : '❌'
          Rails.logger.info("  #{status} #{check[:name]}: #{check[:message]}")
        end

        # Determine overall validation result
        failed_checks = validation_checks.reject { |check| check[:valid] }

        if failed_checks.empty?
          Rails.logger.info("[Signal] All validation checks passed for #{index_cfg[:key]} (#{mode_config[:mode]} mode)")
          { valid: true, reason: 'All checks passed' }
        else
          failed_reasons = failed_checks.pluck(:name).join(', ')
          { valid: false, reason: "Failed checks: #{failed_reasons}" }
        end
      end

      # Get validation mode configuration
      def get_validation_mode_config
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        mode = signals_cfg[:validation_mode] || 'balanced'
        mode_config = signals_cfg.dig(:validation_modes, mode.to_sym) || signals_cfg.dig(:validation_modes, :balanced)

        # Merge with mode name for logging
        mode_config.merge(mode: mode)
      end

      # Validate IV Rank - avoid extreme volatility conditions
      def validate_iv_rank(_index_cfg, series, mode_config = nil)
        mode_config ||= get_validation_mode_config

        # For now, we'll use a simple volatility check based on recent price movement
        # In a full implementation, you'd calculate actual IV rank from historical IV data

        candles = series.candles
        if candles.blank? || candles.size < 5
          return { valid: false, name: 'IV Rank', message: 'Insufficient data for volatility assessment' }
        end

        # Calculate recent volatility as a proxy for IV rank
        # series.candles is an array of Candle objects
        recent_candles = candles.last(5)
        return { valid: false, name: 'IV Rank', message: 'Insufficient recent candles' } if recent_candles.size < 2

        price_changes = recent_candles.each_cons(2).map { |c1, c2| (c2.close - c1.close).abs / c1.close }
        avg_volatility = price_changes.sum / price_changes.size

        # Normalize volatility (this is a simplified approach)
        iv_rank_proxy = [(avg_volatility * 1000), 1.0].min # Cap at 1.0

        max_threshold = mode_config[:iv_rank_max] || 0.8
        min_threshold = mode_config[:iv_rank_min] || 0.1

        if iv_rank_proxy > max_threshold
          { valid: false, name: 'IV Rank', message: "Extreme volatility detected (#{(iv_rank_proxy * 100).round(1)}% > #{(max_threshold * 100).round(1)}%)" }
        elsif iv_rank_proxy < min_threshold
          { valid: false, name: 'IV Rank', message: "Very low volatility (#{(iv_rank_proxy * 100).round(1)}% < #{(min_threshold * 100).round(1)}%)" }
        else
          { valid: true, name: 'IV Rank', message: "Volatility within acceptable range (#{(iv_rank_proxy * 100).round(1)}%)" }
        end
      end

      # Validate theta risk - avoid high theta decay situations
      def validate_theta_risk(_index_cfg, _direction, mode_config = nil)
        mode_config ||= get_validation_mode_config

        current_time = Time.zone.now
        hour = current_time.hour
        minute = current_time.min

        cutoff_hour = mode_config[:theta_risk_cutoff_hour] || 14
        cutoff_minute = mode_config[:theta_risk_cutoff_minute] || 30

        # High theta risk periods (configurable cutoff time)
        if hour > cutoff_hour || (hour == cutoff_hour && minute >= cutoff_minute)
          { valid: false, name: 'Theta Risk', message: "High theta decay risk - too close to market close (after #{cutoff_hour}:#{cutoff_minute.to_s.rjust(2, '0')})" }
        elsif hour >= 14 # After 2:00 PM
          { valid: true, name: 'Theta Risk', message: 'Moderate theta risk - afternoon trading' }
        else
          { valid: true, name: 'Theta Risk', message: 'Low theta risk - early/midday trading' }
        end
      end

      # Enhanced ADX validation with trend strength assessment
      def validate_adx_strength(adx, _supertrend_result, mode_config = nil)
        mode_config ||= get_validation_mode_config

        adx_value = adx[:value].to_f
        min_strength = mode_config[:adx_min_strength] || AlgoConfig.fetch.dig(:signals, :adx, :min_strength).to_f

        if adx_value < min_strength
          { valid: false, name: 'ADX Strength', message: "Weak trend strength (#{adx_value.round(1)} < #{min_strength})" }
        elsif adx_value >= 40
          { valid: true, name: 'ADX Strength', message: "Very strong trend (#{adx_value.round(1)})" }
        elsif adx_value >= 25
          { valid: true, name: 'ADX Strength', message: "Strong trend (#{adx_value.round(1)})" }
        else
          { valid: true, name: 'ADX Strength', message: "Moderate trend (#{adx_value.round(1)})" }
        end
      end

      # Validate trend confirmation with multiple signals
      def validate_trend_confirmation(supertrend_result, series)
        trend = supertrend_result[:trend]

        return { valid: false, name: 'Trend Confirmation', message: 'No trend signal from Supertrend' } if trend.nil?

        # Additional confirmation: check if recent price action supports the trend
        candles = series.candles
        if candles.blank? || candles.size < 3
          return { valid: false, name: 'Trend Confirmation', message: 'Insufficient data for trend confirmation' }
        end

        recent_candles = candles.last(3)

        # Check if recent closes are moving in trend direction
        case trend
        when :bullish
          if recent_candles.last.close > recent_candles.first.close
            { valid: true, name: 'Trend Confirmation', message: 'Bullish trend confirmed by price action' }
          else
            { valid: false, name: 'Trend Confirmation', message: 'Bullish signal not confirmed by recent price action' }
          end
        when :bearish
          if recent_candles.last.close < recent_candles.first.close
            { valid: true, name: 'Trend Confirmation', message: 'Bearish trend confirmed by price action' }
          else
            { valid: false, name: 'Trend Confirmation', message: 'Bearish signal not confirmed by recent price action' }
          end
        else
          { valid: false, name: 'Trend Confirmation', message: 'Unknown trend direction' }
        end
      end

      # Validate market timing - avoid problematic trading times
      def validate_market_timing
        return { valid: true, name: 'Market Timing', message: 'Normal trading hours' }
        current_time = Time.zone.now

        # First check if it's a trading day using Market::Calendar
        unless Market::Calendar.trading_day_today?
          return { valid: false, name: 'Market Timing', message: 'Not a trading day (weekend/holiday)' }
        end

        hour = current_time.hour
        minute = current_time.min

        # Market hours: 9:15 AM to 3:30 PM IST
        market_open = hour > 9 || (hour == 9 && minute >= 15)
        market_close = hour > 15 || (hour == 15 && minute >= 30)

        if !market_open
          { valid: false, name: 'Market Timing', message: 'Market not yet open' }
        elsif market_close
          { valid: false, name: 'Market Timing', message: 'Market closed' }
        elsif hour == 9 && minute < 30
          { valid: true, name: 'Market Timing', message: 'Early market - high volatility period' }
        elsif hour >= 14 && minute >= 30
          { valid: true, name: 'Market Timing', message: 'Late market - theta decay risk' }
        else
          { valid: true, name: 'Market Timing', message: 'Normal trading hours' }
        end
      end

      def calculate_confidence_score(primary_analysis:, confirmation_analysis:, validation_result:)
        base_confidence = 0.5

        # ADX strength factor (0-0.3)
        adx_factor = 0.0
        if primary_analysis[:adx_value]
          adx_value = primary_analysis[:adx_value].to_f
          if adx_value >= 30
            adx_factor = 0.3
          elsif adx_value >= 20
            adx_factor = 0.2
          elsif adx_value >= 15
            adx_factor = 0.1
          end
        end

        # Multi-timeframe confirmation factor (0-0.2)
        confirmation_factor = 0.0
        if confirmation_analysis && confirmation_analysis[:direction] == primary_analysis[:direction]
          confirmation_factor = 0.2
        end

        # Validation factor (0-0.1)
        validation_factor = validation_result[:valid] ? 0.1 : 0.0

        # Supertrend strength factor (0-0.1)
        supertrend_factor = 0.0
        if primary_analysis[:supertrend] && primary_analysis[:supertrend][:last_value]
          # Higher supertrend values indicate stronger trend
          st_value = primary_analysis[:supertrend][:last_value].to_f
          supertrend_factor = [st_value / 1000.0, 0.1].min # Cap at 0.1
        end

        total_confidence = base_confidence + adx_factor + confirmation_factor + validation_factor + supertrend_factor
        [total_confidence, 1.0].min # Cap at 1.0
      end

      def decide_direction(supertrend_result, adx_value, min_strength:, timeframe_label:)
        min_required = min_strength.to_f
        adx_numeric = adx_value.to_f

        Rails.logger.debug { "[Signal] ADX check(#{timeframe_label}): value=#{adx_numeric}, min_required=#{min_required}" }

        # Only apply ADX filter if min_required is positive (i.e., ADX filter is enabled)
        if min_required.positive? && adx_numeric < min_required
          Rails.logger.info("[Signal] ADX too weak on #{timeframe_label}: #{adx_numeric} < #{min_required}")
          return :avoid
        end

        if supertrend_result.blank? || supertrend_result[:trend].nil?
          Rails.logger.warn("[Signal] Supertrend result invalid on #{timeframe_label}: #{supertrend_result}")
          return :avoid
        end

        trend = supertrend_result[:trend]
        Rails.logger.debug { "[Signal] Supertrend trend(#{timeframe_label}): #{trend}" }

        # Use the trend from Supertrend calculation
        case trend
        when :bullish
          Rails.logger.info("[Signal] Bullish signal confirmed on #{timeframe_label}: ADX=#{adx_numeric}, Supertrend=#{trend}")
          :bullish
        when :bearish
          Rails.logger.info("[Signal] Bearish signal confirmed on #{timeframe_label}: ADX=#{adx_numeric}, Supertrend=#{trend}")
          :bearish
        else
          Rails.logger.info("[Signal] Neutral/unknown trend on #{timeframe_label}: #{trend}")
          :avoid
        end
      end
    end
  end
end
