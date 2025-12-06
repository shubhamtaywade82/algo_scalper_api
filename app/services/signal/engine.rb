# frozen_string_literal: true

module Signal
  class Engine
    class << self
      def run_for(index_cfg)
        # Skip signal generation if market is closed (after 3:30 PM IST)
        if TradingSession::Service.market_closed?
          Rails.logger.debug { "[Signal] Market closed - skipping analysis for #{index_cfg[:key]}" }
          return
        end

        Rails.logger.info("\n\n[Signal] ----------------------------------------------------- Starting analysis for #{index_cfg[:key]} (IDX_I) --------------------------------------------------------")

        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.error("[Signal] Could not find instrument for #{index_cfg[:key]}")
          return
        end

        # Phase 1: Quick No-Trade pre-check (BEFORE expensive signal generation)
        # Returns validation result + option chain data for reuse in Phase 2
        # Can be disabled via config: signals.enable_no_trade_engine = false
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        enable_no_trade_engine = signals_cfg.fetch(:enable_no_trade_engine, true)

        cached_option_chain = nil
        cached_bars_1m = nil

        if enable_no_trade_engine
          quick_no_trade_result = quick_no_trade_precheck(index_cfg: index_cfg, instrument: instrument)
          unless quick_no_trade_result[:allowed]
            Rails.logger.warn(
              "[Signal] NO-TRADE pre-check blocked #{index_cfg[:key]}: " \
              "score=#{quick_no_trade_result[:score]}/11, reasons=#{quick_no_trade_result[:reasons].join('; ')}"
            )
            return
          end

          # Store option chain data from Phase 1 for reuse in Phase 2
          cached_option_chain = quick_no_trade_result[:option_chain_data]
          cached_bars_1m = quick_no_trade_result[:bars_1m]
        else
          Rails.logger.info("[Signal] NoTradeEngine Phase 1 DISABLED for #{index_cfg[:key]} - skipping pre-check")
        end
        primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_supertrend_signal = signals_cfg.fetch(:enable_supertrend_signal, true)
        enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, false)
        confirmation_tf = (signals_cfg[:confirmation_timeframe].presence&.to_s if enable_confirmation)

        # Check if strategy-based recommendations are enabled
        use_strategy_recommendations = signals_cfg.fetch(:use_strategy_recommendations, false)

        # Rails.logger.debug { "[Signal] Primary timeframe: #{primary_tf}, confirmation timeframe: #{confirmation_tf || 'none'} (enabled: #{enable_confirmation})" }

        # Get strategy recommendation if enabled - use best strategy for this index
        strategy_recommendation = nil
        effective_timeframe = primary_tf
        if use_strategy_recommendations
          # Get best strategy for this index (across all timeframes)
          strategy_recommendation = StrategyRecommender.best_for_index(symbol: index_cfg[:key])
          if strategy_recommendation && strategy_recommendation[:recommended]
            # Use the recommended strategy's timeframe instead of config timeframe
            effective_timeframe = "#{strategy_recommendation[:interval]}m"
            Rails.logger.info("[Signal] Using recommended strategy for #{index_cfg[:key]}: #{strategy_recommendation[:strategy_name]} (#{strategy_recommendation[:interval]}min) - Expectancy: #{strategy_recommendation[:expectancy]}% | Switching timeframe from #{primary_tf} to #{effective_timeframe}")
          elsif strategy_recommendation
            Rails.logger.warn("[Signal] Strategy recommendation found for #{index_cfg[:key]} but not recommended (negative expectancy: #{strategy_recommendation[:expectancy]}%) - falling back to Supertrend+ADX")
            strategy_recommendation = nil
          else
            Rails.logger.warn("[Signal] No strategy recommendation found for #{index_cfg[:key]} - falling back to Supertrend+ADX")
          end
        end

        # Check if modular indicator system is enabled
        use_multi_indicator = signals_cfg.fetch(:use_multi_indicator_strategy, false)

        # Load common config variables (needed for confirmation timeframe)
        supertrend_cfg = signals_cfg[:supertrend] || { period: 7, multiplier: 3.0 }
        adx_cfg = signals_cfg[:adx] || {}
        enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, false)

        # Use strategy-based analysis if recommendation is available and enabled
        if use_strategy_recommendations && strategy_recommendation && strategy_recommendation[:recommended]
          primary_analysis = analyze_with_recommended_strategy(
            index_cfg: index_cfg,
            instrument: instrument,
            timeframe: effective_timeframe,
            strategy_recommendation: strategy_recommendation
          )
        elsif use_multi_indicator
          # Use modular multi-indicator system
          primary_analysis = analyze_with_multi_indicators(
            index_cfg: index_cfg,
            instrument: instrument,
            timeframe: primary_tf,
            signals_cfg: signals_cfg
          )
        elsif enable_supertrend_signal
          # Traditional Supertrend + ADX analysis (1m signal)
          unless supertrend_cfg
            Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
            return
          end

          # Get per-index ADX thresholds (if specified) or fall back to global
          index_adx_thresholds = index_cfg[:adx_thresholds] || {}
          primary_adx_threshold = index_adx_thresholds[:primary_min_strength] || adx_cfg[:min_strength]

          # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
          adx_min_strength = enable_adx_filter ? primary_adx_threshold : 0

          primary_analysis = analyze_timeframe(
            index_cfg: index_cfg,
            instrument: instrument,
            timeframe: primary_tf,
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: adx_min_strength
          )
        else
          Rails.logger.warn("[Signal] Supertrend signal disabled for #{index_cfg[:key]} - skipping analysis")
          return
        end

        unless primary_analysis[:status] == :ok
          Rails.logger.warn("[Signal] Primary timeframe analysis unavailable for #{index_cfg[:key]}: #{primary_analysis[:message]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        final_direction = primary_analysis[:direction]
        confirmation_analysis = nil

        # Skip confirmation timeframe when using strategy recommendations or multi-indicator system
        # (strategies were backtested as standalone systems, multi-indicator can combine indicators internally)
        if confirmation_tf.present? && !(use_strategy_recommendations && strategy_recommendation && strategy_recommendation[:recommended]) && !use_multi_indicator
          mode_config = get_validation_mode_config

          # Get per-index ADX thresholds (if specified) or fall back to global
          index_adx_thresholds = index_cfg[:adx_thresholds] || {}
          confirmation_adx_threshold = index_adx_thresholds[:confirmation_min_strength] ||
                                       mode_config[:adx_confirmation_min_strength] ||
                                       adx_cfg[:confirmation_min_strength] ||
                                       adx_cfg[:min_strength]

                                       pp confirmation_adx_threshold
                                       pp enable_adx_filter
                                       pp adx_cfg
                                       pp index_adx_thresholds
                                       pp mode_config
                                       pp adx_cfg[:confirmation_min_strength]
                                       pp adx_cfg[:min_strength]
                                       pp index_adx_thresholds[:confirmation_min_strength]
                                       pp mode_config[:adx_confirmation_min_strength]
          # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
          confirmation_adx_min = if enable_adx_filter
                                   confirmation_adx_threshold
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
          # Rails.logger.info("[Signal] Multi-timeframe decision for #{index_cfg[:key]}: primary=#{primary_analysis[:direction]} confirmation=#{confirmation_analysis[:direction]} final=#{final_direction}")
        elsif confirmation_tf.present? && use_strategy_recommendations && strategy_recommendation && strategy_recommendation[:recommended]
          Rails.logger.info("[Signal] Skipping confirmation timeframe for #{index_cfg[:key]} (using strategy recommendation: #{strategy_recommendation[:strategy_name]})")
        elsif confirmation_tf.present? && use_multi_indicator
          Rails.logger.info("[Signal] Skipping confirmation timeframe for #{index_cfg[:key]} (using multi-indicator system - indicators can be combined via confirmation_mode)")
        end

        if final_direction == :avoid
          if use_strategy_recommendations && strategy_recommendation && strategy_recommendation[:recommended]
            Rails.logger.info("[Signal] NOT proceeding for #{index_cfg[:key]}: #{strategy_recommendation[:strategy_name]} did not generate a signal (conditions not met)")
          else
            Rails.logger.info("[Signal] NOT proceeding for #{index_cfg[:key]}: multi-timeframe bias mismatch or weak trend")
          end
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        primary_series = primary_analysis[:series]
        validation_result = comprehensive_validation(index_cfg, final_direction, primary_series,
                                                     primary_analysis[:supertrend], { value: primary_analysis[:adx_value] })
        unless validation_result[:valid]
          Rails.logger.warn("[Signal] NOT proceeding for #{index_cfg[:key]}: #{validation_result[:reason]}")
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
          timeframe: effective_timeframe,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: confidence_score,
          metadata: {
            confirmation_timeframe: confirmation_tf,
            confirmation_direction: confirmation_analysis&.dig(:direction),
            validation_passed: validation_result[:valid],
            state_count: state_snapshot[:count],
            state_multiplier: state_snapshot[:multiplier],
            strategy_used: strategy_recommendation&.dig(:strategy_name),
            original_timeframe: primary_tf
          }
        )

        # Rails.logger.info("[Signal] Signal state for #{index_cfg[:key]}: count=#{state_snapshot[:count]} multiplier=#{state_snapshot[:multiplier]}")

        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: final_direction)

        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{final_direction}")
          return
        end

        Rails.logger.info("[Signal] Found #{picks.size} option picks for #{index_cfg[:key]}: #{picks.pluck(:symbol).join(', ')}")

        # Phase 2: Detailed No-Trade validation (AFTER signal generation, with full context)
        # Reuses option chain and bars_1m from Phase 1 to avoid duplicate fetches
        # Can be disabled via config: signals.enable_no_trade_engine = false
        if enable_no_trade_engine
          detailed_no_trade = validate_no_trade_conditions(
            index_cfg: index_cfg,
            instrument: instrument,
            direction: final_direction,
            cached_option_chain: cached_option_chain,
            cached_bars_1m: cached_bars_1m
          )

          unless detailed_no_trade[:allowed]
            Rails.logger.warn(
              "[Signal] NO-TRADE detailed validation blocked #{index_cfg[:key]}: " \
              "score=#{detailed_no_trade[:score]}/11, reasons=#{detailed_no_trade[:reasons].join('; ')}"
            )
            return
          end
        else
          Rails.logger.info("[Signal] NoTradeEngine Phase 2 DISABLED for #{index_cfg[:key]} - skipping detailed validation")
        end

        picks.each_with_index do |pick, _index|
          # Rails.logger.info("[Signal] Attempting entry #{index + 1}/#{picks.size} for #{index_cfg[:key]}: #{pick[:symbol]} (scale x#{state_snapshot[:multiplier]})")
          result = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: final_direction,
            scale_multiplier: state_snapshot[:multiplier],
            confidence_score: confidence_score
          )

          if result
            # Rails.logger.info("[Signal] Entry successful for #{index_cfg[:key]}: #{pick[:symbol]}")
          else
            Rails.logger.debug { "[Signal] Entry failed for #{index_cfg[:key]}: #{pick[:symbol]} #{result}" }
          end
        end

        # Rails.logger.info("[Signal] Completed analysis for #{index_cfg[:key]}")
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

        # Rails.logger.info("[Signal] Fetched #{series.candles.size} candles for #{index_cfg[:key]} @ #{timeframe}")
        # Rails.logger.debug { "[Signal] Adaptive Supertrend config: #{supertrend_cfg}" }

        st_service = Indicators::Supertrend.new(series: series, **supertrend_cfg)
        st = st_service.call
        st[:adaptive_multipliers]&.compact&.last
        # Rails.logger.info(
        #   "[Signal] Supertrend(#{timeframe}) for #{index_cfg[:key]}: trend=#{st[:trend]} last_value=#{st[:last_value]} multiplier=#{last_multiplier}"
        # )

        adx_value = instrument.adx(14, interval: interval)
        # Rails.logger.info("[Signal] ADX(#{timeframe}) for #{index_cfg[:key]}: #{adx_value}")

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
        enable_supertrend_signal = signals_cfg.fetch(:enable_supertrend_signal, true)
        enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, false)
        confirmation_tf = (signals_cfg[:confirmation_timeframe].presence&.to_s if enable_confirmation)

        unless enable_supertrend_signal
          Rails.logger.warn("[Signal] Supertrend signal disabled for #{index_cfg[:key]}")
          return { status: :error, message: 'Supertrend signal disabled' }
        end

        supertrend_cfg = signals_cfg[:supertrend]
        unless supertrend_cfg
          Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
          return { status: :error, message: 'Supertrend configuration missing' }
        end

        adx_cfg = signals_cfg[:adx] || {}
        enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, false)

        # Get per-index ADX thresholds (if specified) or fall back to global
        index_adx_thresholds = index_cfg[:adx_thresholds] || {}
        primary_adx_threshold = index_adx_thresholds[:primary_min_strength] || adx_cfg[:min_strength]
        confirmation_adx_threshold = index_adx_thresholds[:confirmation_min_strength] || adx_cfg[:confirmation_min_strength] || adx_cfg[:min_strength]

        # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
        adx_min_strength = enable_adx_filter ? primary_adx_threshold : 0

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
                                   confirmation_adx_threshold
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
        # Rails.logger.info("[Signal] Running comprehensive validation for #{index_cfg[:key]} #{direction} (mode: #{mode_config[:mode]})")

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
          # Rails.logger.debug('[Signal] ADX validation skipped (filter disabled)')
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
        # Rails.logger.info("[Signal] Validation Results (#{mode_config[:mode]} mode):")
        validation_checks.each do |check|
          check[:valid] ? '✅' : '❌'
          # Rails.logger.info("  #{status} #{check[:name]}: #{check[:message]}")
        end

        # Determine overall validation result
        failed_checks = validation_checks.reject { |check| check[:valid] }

        if failed_checks.empty?
          # Rails.logger.info("[Signal] All validation checks passed for #{index_cfg[:key]} (#{mode_config[:mode]} mode)")
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
        mode_config = signals_cfg.dig(:validation_modes,
                                      mode.to_sym) || signals_cfg.dig(:validation_modes, :balanced) || {}

        # Ensure mode_config is always a Hash (handle edge cases where config might be wrong type)
        mode_config = {} unless mode_config.is_a?(Hash)

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

      def analyze_with_recommended_strategy(index_cfg:, instrument:, timeframe:, strategy_recommendation:)
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

        strategy_class = strategy_recommendation[:strategy_class]
        strategy_config = {}

        # Prepare strategy-specific configuration
        if strategy_class == SupertrendAdxStrategy
          signals_cfg = AlgoConfig.fetch[:signals] || {}
          strategy_config = {
            supertrend_cfg: signals_cfg[:supertrend] || { period: 7, multiplier: 3 },
            adx_min_strength: signals_cfg.dig(:adx, :min_strength) || 20
          }
        end

        # Use the last candle index for signal generation
        current_index = series.candles.size - 1

        Rails.logger.info("[Signal] Analyzing #{index_cfg[:key]} with #{strategy_recommendation[:strategy_name]} at index #{current_index} (#{series.candles.size} candles, timeframe: #{timeframe})")

        result = Signal::StrategyAdapter.analyze_with_strategy(
          strategy_class: strategy_class,
          series: series,
          index: current_index,
          strategy_config: strategy_config
        )

        pp series.candles.last
        pp series.candles.first
        if result[:status] == :ok && result[:direction] == :avoid
          Rails.logger.info("[Signal] #{strategy_recommendation[:strategy_name]} did not generate a signal for #{index_cfg[:key]} - checking conditions...")
          # Log why signal might not be generated
          last_candle = series.candles[current_index]
          if last_candle
            # Convert timestamp to IST timezone explicitly
            ist_time = last_candle.timestamp.in_time_zone('Asia/Kolkata')
            hour = ist_time.hour
            minute = ist_time.min
            # Market hours: 9:15 AM to 3:30 PM IST (checking up to 3:30 PM)
            in_trading_hours = (hour > 9 || (hour == 9 && minute >= 15)) && (hour < 15 || (hour == 15 && minute < 30))
            Rails.logger.info("[Signal] Last candle time: #{ist_time.strftime('%H:%M %Z')} | In trading hours: #{in_trading_hours} | Candles available: #{series.candles.size}")
          end
        end

        # Convert to standard format with supertrend and adx placeholders for compatibility
        if result[:status] == :ok
          {
            status: :ok,
            series: result[:series],
            supertrend: { trend: result[:direction] == :bullish ? :bullish : :bearish, last_value: nil },
            adx_value: result[:confidence] || 0,
            direction: result[:direction],
            last_candle_timestamp: result[:last_candle_timestamp],
            strategy_confidence: result[:confidence]
          }
        else
          result
        end
      rescue StandardError => e
        Rails.logger.error("[Signal] Strategy-based analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      def analyze_with_multi_indicators(index_cfg:, instrument:, timeframe:, signals_cfg:)
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

        # Get enabled indicators from configuration
        indicator_configs = signals_cfg[:indicators] || []
        enabled_indicators = indicator_configs.select { |ic| ic[:enabled] != false }

        if enabled_indicators.empty?
          Rails.logger.warn("[Signal] No enabled indicators configured for #{index_cfg[:key]}")
          return { status: :error, message: 'No enabled indicators' }
        end

        # Get preset from config (algo.yml preferred, ENV as fallback)
        preset_name = signals_cfg[:indicator_preset]&.to_sym || ENV['INDICATOR_PRESET']&.to_sym || :moderate
        threshold_preset = Indicators::ThresholdConfig.get_preset(preset_name)

        # Merge global config with indicator configs
        global_config = {
          supertrend_cfg: signals_cfg[:supertrend] || { period: 7, multiplier: 3.0 },
          trading_hours_filter: true,
          indicator_preset: preset_name # Pass preset name to indicators
        }

        # Apply threshold config to individual indicators
        enabled_indicators.each do |ic|
          indicator_type = ic[:type].to_s.downcase.to_sym
          ic[:config] ||= {}

          # Merge threshold config for this indicator type
          if threshold_preset[indicator_type] && ic[:config].is_a?(Hash)
            ic[:config] = (ic[:config] || {}).merge(threshold_preset[indicator_type])
          end
        end

        # Get per-index ADX thresholds if specified (overrides preset)
        index_adx_thresholds = index_cfg[:adx_thresholds] || {}
        if index_adx_thresholds[:primary_min_strength]
          # Update ADX indicator config with per-index threshold
          enabled_indicators.each do |ic|
            if ic[:type].to_s.downcase == 'adx'
              ic[:config] ||= {}
              ic[:config][:min_strength] = index_adx_thresholds[:primary_min_strength]
            end
          end
        end

        # Build multi-indicator strategy
        confirmation_mode = signals_cfg[:confirmation_mode] || :all
        min_confidence = signals_cfg[:min_confidence] || 60

        # Merge threshold config into global_config for MultiIndicatorStrategy
        global_config = global_config.merge(threshold_preset[:multi_indicator] || {})

        strategy = MultiIndicatorStrategy.new(
          series: series,
          indicators: enabled_indicators,
          confirmation_mode: confirmation_mode,
          min_confidence: min_confidence,
          **global_config
        )

        # Use the last candle index for signal generation
        current_index = series.candles.size - 1
        signal = strategy.generate_signal(current_index)

        if signal.nil?
          Rails.logger.debug { "[Signal] Multi-indicator strategy did not generate signal for #{index_cfg[:key]} at index #{current_index}" }
          return {
            status: :ok,
            series: series,
            supertrend: { trend: nil, last_value: nil },
            adx_value: 0,
            direction: :avoid,
            last_candle_timestamp: series.candles.last&.timestamp
          }
        end

        # Convert signal to direction
        direction = signal[:type] == :ce ? :bullish : :bearish

        # Log confluence information
        if signal[:confluence]
          confluence = signal[:confluence]
          Rails.logger.info("[Signal] Confluence for #{index_cfg[:key]}: score=#{confluence[:score]}% strength=#{confluence[:strength]} (#{confluence[:agreeing_count]}/#{confluence[:total_indicators]} indicators agree on #{confluence[:dominant_direction]})")
          confluence[:breakdown].each do |ind|
            status = ind[:agrees] ? '✓' : '✗'
            Rails.logger.debug { "[Signal]   #{status} #{ind[:name]}: #{ind[:direction]} (confidence: #{ind[:confidence]})" }
          end
        end

        # Extract indicator values for compatibility
        # Try to get supertrend and ADX values if available
        supertrend_value = nil
        adx_value = 0

        enabled_indicators.each do |ic|
          indicator_name = ic[:type].to_s.downcase
          if %w[supertrend st].include?(indicator_name)
            # Calculate supertrend for compatibility
            st_cfg = global_config[:supertrend_cfg]
            st_service = Indicators::Supertrend.new(series: series, **st_cfg)
            st_result = st_service.call
            supertrend_value = st_result[:last_value] if st_result
          elsif indicator_name == 'adx'
            adx_value = series.adx(ic.dig(:config, :period) || 14) || 0
          end
        end

        {
          status: :ok,
          series: series,
          supertrend: { trend: direction, last_value: supertrend_value },
          adx_value: adx_value,
          direction: direction,
          last_candle_timestamp: series.candles.last&.timestamp,
          confidence: signal[:confidence],
          confluence: signal[:confluence]
        }
      rescue StandardError => e
        Rails.logger.error("[Signal] Multi-indicator analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}")
        Rails.logger.error("[Signal] Backtrace: #{e.backtrace.first(5).join(', ')}")
        { status: :error, message: e.message }
      end

      def decide_direction(supertrend_result, adx_value, min_strength:, timeframe_label:)
        min_required = min_strength.to_f
        adx_numeric = adx_value.to_f

        # Rails.logger.debug { "[Signal] ADX check(#{timeframe_label}): value=#{adx_numeric}, min_required=#{min_required}" }

        # Only apply ADX filter if min_required is positive (i.e., ADX filter is enabled)
        if min_required.positive? && adx_numeric < min_required
          # Rails.logger.info("[Signal] ADX too weak on #{timeframe_label}: #{adx_numeric} < #{min_required}")
          return :avoid
        end

        if supertrend_result.blank? || supertrend_result[:trend].nil?
          Rails.logger.warn("[Signal] Supertrend result invalid on #{timeframe_label}: #{supertrend_result}")
          return :avoid
        end

        trend = supertrend_result[:trend]
        # Rails.logger.debug { "[Signal] Supertrend trend(#{timeframe_label}): #{trend}" }

        # Use the trend from Supertrend calculation
        case trend
        when :bullish
          # Rails.logger.info("[Signal] Bullish signal confirmed on #{timeframe_label}: ADX=#{adx_numeric}, Supertrend=#{trend}")
          :bullish
        when :bearish
          # Rails.logger.info("[Signal] Bearish signal confirmed on #{timeframe_label}: ADX=#{adx_numeric}, Supertrend=#{trend}")
          :bearish
        else
          # Rails.logger.info("[Signal] Neutral/unknown trend on #{timeframe_label}: #{trend}")
          :avoid
        end
      end

      # Phase 1: Quick No-Trade pre-check (before expensive signal generation)
      # Checks only fast/cheap conditions: time windows, basic structure, basic option chain
      # @param index_cfg [Hash] Index configuration
      # @param instrument [Instrument] Instrument object
      # @return [Hash] Validation result with :allowed, :score, :reasons
      def quick_no_trade_precheck(index_cfg:, instrument:)
        current_time = Time.current.strftime('%H:%M')
        reasons = []
        score = 0
        option_chain_data = nil
        bars_1m = nil

        # Time windows (fastest check - no data needed)
        if current_time >= '09:15' && current_time <= '09:18'
          reasons << 'Avoid first 3 minutes'
          score += 1
        end

        if current_time >= '11:20' && current_time <= '13:30'
          reasons << 'Lunch-time theta zone'
          score += 1
        end

        if current_time > '15:05'
          reasons << 'Post 3:05 PM - theta crush'
          score += 1
        end

        # Basic structure check (needs bars_1m)
        bars_1m = instrument.candle_series(interval: '1')
        if bars_1m&.candles&.any?
          bars_1m_array = bars_1m.candles

          # NOTE: BOS check removed from Phase 1 to avoid duplicate penalty
          # BOS is checked in Phase 2 with full context

          # Basic volatility check
          range_pct = Entries::RangeUtils.range_pct(bars_1m_array.last(10))
          if range_pct < 0.1
            reasons << 'Low volatility: 10m range < 0.1%'
            score += 1
          end
        end

        # Basic option chain check (IV threshold, spread)
        expiry_list = instrument.expiry_list
        expiry_date = expiry_list&.first
        if expiry_date
          option_chain_raw = instrument.fetch_option_chain(expiry_date)
          option_chain_data = option_chain_raw.is_a?(Hash) ? option_chain_raw : nil

          if option_chain_data
            chain_wrapper = Entries::OptionChainWrapper.new(
              chain_data: option_chain_data,
              index_key: index_cfg[:key]
            )

            min_iv_threshold = index_cfg[:key].to_s.upcase.include?('BANK') ? 13 : 10
            if chain_wrapper.atm_iv && chain_wrapper.atm_iv < min_iv_threshold
              reasons << "IV too low (#{chain_wrapper.atm_iv.round(2)} < #{min_iv_threshold})"
              score += 1
            end

            if chain_wrapper.spread_wide?
              reasons << 'Wide bid-ask spread'
              score += 1
            end
          end
        end

        {
          allowed: score < 3,
          score: score,
          reasons: reasons,
          option_chain_data: option_chain_data, # Return for reuse in Phase 2
          bars_1m: bars_1m # Return for reuse in Phase 2
        }
      rescue StandardError => e
        Rails.logger.error("[Signal] Quick No-Trade pre-check failed: #{e.class} - #{e.message}")
        # On error, allow to proceed (fail open)
        { allowed: true, score: 0, reasons: ["Pre-check error: #{e.message}"], option_chain_data: nil, bars_1m: nil }
      end

      # Phase 2: Detailed No-Trade validation (after signal generation, with full context)
      # Reuses option chain and bars_1m from Phase 1 to avoid duplicate fetches
      # @param index_cfg [Hash] Index configuration
      # @param instrument [Instrument] Instrument object
      # @param direction [Symbol] Trade direction (:bullish or :bearish)
      # @param cached_option_chain [Hash, nil] Option chain data from Phase 1 (optional)
      # @param cached_bars_1m [CandleSeries, nil] 1m bars from Phase 1 (optional)
      # @return [Hash] Validation result with :allowed, :score, :reasons
      def validate_no_trade_conditions(index_cfg:, instrument:, direction:, cached_option_chain: nil,
                                       cached_bars_1m: nil)
        # Reuse bars_1m from Phase 1 if available, otherwise fetch
        bars_1m = cached_bars_1m || instrument.candle_series(interval: '1')

        # Always fetch bars_5m (needed for ADX/DI calculations)
        bars_5m = instrument.candle_series(interval: '5')

        return { allowed: true, score: 0, reasons: [] } unless bars_1m&.candles&.any? && bars_5m&.candles&.any?

        # Reuse option chain from Phase 1 if available, otherwise fetch
        option_chain_data = cached_option_chain
        unless option_chain_data
          expiry_list = instrument.expiry_list
          expiry_date = expiry_list&.first
          option_chain_raw = expiry_date ? instrument.fetch_option_chain(expiry_date) : nil
          option_chain_data = option_chain_raw.is_a?(Hash) ? option_chain_raw : nil
        end

        # Build context with full No-Trade Engine validation
        ctx = Entries::NoTradeContextBuilder.build(
          index: index_cfg[:key],
          bars_1m: bars_1m.candles,
          bars_5m: bars_5m.candles,
          option_chain: option_chain_data,
          time: Time.current
        )

        # Validate with No-Trade Engine
        result = Entries::NoTradeEngine.validate(ctx)

        {
          allowed: result.allowed,
          score: result.score,
          reasons: result.reasons
        }
      rescue StandardError => e
        Rails.logger.error("[Signal] No-Trade Engine validation failed: #{e.class} - #{e.message}")
        # On error, allow trade (fail open) but log the error
        { allowed: true, score: 0, reasons: ["Validation error: #{e.message}"] }
      end
    end
  end
end
