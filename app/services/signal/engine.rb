# frozen_string_literal: true
# rubocop:disable Metrics/BlockNesting

# rubocop:disable Metrics/BlockNesting

module Signal
  # Stock Supertrend options-buying pipeline: 1m flip → chop gate → ATM strike → EntryGuard.
  class Engine
    class << self
      def run_for(index_cfg, regime_state: nil)
        # Skip signal generation if market is closed (after 3:30 PM IST)
        if defined?(TradingSession::Service) && TradingSession::Service.respond_to?(:market_closed?) && TradingSession::Service.market_closed?
          Rails.logger.debug { "[Signal] Market closed - skipping analysis for #{index_cfg[:key]}" }
          return
        end

        Rails.logger.info("\n\n[Signal] ----------------------------------------------------- Starting analysis for #{index_cfg[:key]} (IDX_I) --------------------------------------------------------")

        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.error("[Signal] Could not find instrument for #{index_cfg[:key]}")
          return
        end

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        entry_primary = (
          signals_cfg.dig(:entry_strategy, :primary) || signals_cfg[:entry_strategy].to_s
        ).to_s.strip.downcase

        primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, true)
        confirmation_tf = if enable_confirmation && signals_cfg[:confirmation_timeframe].present?
                            signals_cfg[:confirmation_timeframe].to_s
                          end

        if entry_primary == 'supertrend'
          # ===== SUPERTREND-ONLY ENTRY (entry_strategy.primary: supertrend) =====
          # Direction from SupertrendTrend (flip only). No Index TA, no strategy recs,
          # no confirmation TF, no DirectionGate, no ADX/trend_confirmation in validation.
          use_strategy_recommendations = true
          strategy_recommendation = { strategy_name: 'supertrend_trend', recommended: true }
          effective_timeframe = primary_tf

          supertrend_cfg = signals_cfg[:supertrend]
          unless supertrend_cfg
            Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
            return
          end

          primary_analysis = analyze_timeframe(
            index_cfg: index_cfg,
            instrument: instrument,
            timeframe: primary_tf,
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 0
          )
          unless primary_analysis[:status] == :ok
            Rails.logger.warn("[Signal] Primary timeframe analysis unavailable for #{index_cfg[:key]}: #{primary_analysis[:message]}")
            Signal::StateTracker.reset(index_cfg[:key])
            return
          end

          trend_direction = SupertrendTrend.direction(
            series: primary_analysis[:series],
            supertrend_result: primary_analysis[:supertrend]
          )
          if trend_direction == :none
            Rails.logger.info("[Signal] SupertrendTrend :none — no trade for #{index_cfg[:key]}")
            Signal::StateTracker.reset(index_cfg[:key])
            return
          end

          final_direction = trend_direction == :long ? :bullish : :bearish
          confirmation_analysis = nil
          primary_series = primary_analysis[:series]
          validation_result = comprehensive_validation(
            index_cfg, final_direction, primary_series,
            primary_analysis[:supertrend], { value: primary_analysis[:adx_value] },
            supertrend_only: true
          )
        else
          # ===== INDEX TECHNICAL ANALYSIS STEP =====
          # Perform multi-timeframe TA analysis before signal generation
          # Can be disabled via config: signals.enable_index_ta = false
          enable_index_ta = signals_cfg.fetch(:enable_index_ta, true)
          ta_result = nil

          if enable_index_ta
            ta_timeframes = signals_cfg[:ta_timeframes] || [5, 15, 60]
            ta_days_back = signals_cfg[:ta_days_back] || 30
            ta_min_confidence = signals_cfg[:ta_min_confidence] || 0.6

            index_symbol = index_cfg[:key].to_s.downcase.to_sym
            ta_analyzer = IndexTechnicalAnalyzer.new(index_symbol)
            ta_analysis = ta_analyzer.call(timeframes: ta_timeframes, days_back: ta_days_back)

            if ta_analysis[:success] && ta_analyzer.success?
              ta_result = ta_analyzer.result

              # If TA suggests neutral or low confidence, consider skipping
              if ta_result[:signal] == :neutral || ta_result[:confidence] < ta_min_confidence
                Rails.logger.info(
                  "[Signal] Skipping signal generation for #{index_cfg[:key]}: " \
                  "TA signal=#{ta_result[:signal]}, confidence=#{ta_result[:confidence].round(2)} " \
                  "(min required=#{ta_min_confidence})"
                )
                return
              end

              Rails.logger.info(
                "[Signal] Index TA for #{index_cfg[:key]}: signal=#{ta_result[:signal]}, " \
                "confidence=#{ta_result[:confidence].round(2)}, bias=#{ta_result.dig(:bias_summary, :summary, :bias)}"
              )
            else
              Rails.logger.warn(
                "[Signal] Index TA failed for #{index_cfg[:key]}: #{ta_analyzer.error} - continuing with signal generation"
              )
            end
          else
            Rails.logger.info("[Signal] Index TA DISABLED for #{index_cfg[:key]} - skipping TA step")
          end

          primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
          enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, true)
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

          # Use strategy-based analysis if recommendation is available and enabled
          if use_strategy_recommendations && strategy_recommendation && strategy_recommendation[:recommended]
            primary_analysis = analyze_with_recommended_strategy(
              index_cfg: index_cfg,
              instrument: instrument,
              timeframe: effective_timeframe,
              strategy_recommendation: strategy_recommendation
            )
          else
            # Fallback to traditional Supertrend + ADX analysis
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
          end

          unless primary_analysis[:status] == :ok
            Rails.logger.warn("[Signal] Primary timeframe analysis unavailable for #{index_cfg[:key]}: #{primary_analysis[:message]}")
            Signal::StateTracker.reset(index_cfg[:key])
            return
          end

          final_direction = primary_analysis[:direction]
          confirmation_analysis = nil

          # Skip confirmation timeframe when using strategy recommendations
          # (strategies were backtested as standalone systems)
          if confirmation_tf.present? && !(use_strategy_recommendations && strategy_recommendation && strategy_recommendation[:recommended])
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
            # Rails.logger.info("[Signal] Multi-timeframe decision for #{index_cfg[:key]}: primary=#{primary_analysis[:direction]} confirmation=#{confirmation_analysis[:direction]} final=#{final_direction}")
          elsif confirmation_tf.present? && use_strategy_recommendations && strategy_recommendation && strategy_recommendation[:recommended]
            Rails.logger.info("[Signal] Skipping confirmation timeframe for #{index_cfg[:key]} (using strategy recommendation: #{strategy_recommendation[:strategy_name]})")
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

          # ===== DIRECTION GATE (HARD FILTER) =====
          # MUST run BEFORE SMC, AVRZ, Permission resolution, or any entry logic.
          # Blocks impossible trades based on market regime.
          # Can be disabled via config: signals.enable_direction_gate = false
          enable_direction_gate = signals_cfg.fetch(:enable_direction_gate, true)

          if enable_direction_gate
            trade_side = final_direction == :bullish ? :CE : :PE
            candles_15m = instrument.candle_series(interval: '15')&.candles || []
            regime = Market::MarketRegimeResolver.resolve(candles_15m: candles_15m)

            unless Trading::DirectionGate.allow?(regime: regime, side: trade_side)
              Rails.logger.info(
                "[Signal] DirectionGate BLOCKED #{index_cfg[:key]}: #{trade_side} trade in #{regime} regime"
              )
              Signal::StateTracker.reset(index_cfg[:key])
              return
            end
            Rails.logger.debug { "[Signal] DirectionGate ALLOWED #{index_cfg[:key]}: #{trade_side} trade in #{regime} regime" }
          else
            Rails.logger.debug { "[Signal] DirectionGate DISABLED for #{index_cfg[:key]} - skipping regime check" }
          end
          # ===== END DIRECTION GATE =====

          primary_series = primary_analysis[:series]
          validation_result = comprehensive_validation(index_cfg, final_direction, primary_series,
                                                       primary_analysis[:supertrend], { value: primary_analysis[:adx_value] })
        end

        unless validation_result[:valid]
          Rails.logger.warn("[Signal] NOT proceeding for #{index_cfg[:key]}: #{validation_result[:reason]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        # ===== ENTRY QUALITY FILTER =====
        quality_result = Signal::EntryQualityFilter.evaluate(
          series: primary_series,
          supertrend_result: primary_analysis[:supertrend],
          adx_value: primary_analysis[:adx_value],
          direction: final_direction,
          regime: regime,
          index_key: index_cfg[:key]
        )
        unless quality_result[:pass]
          Rails.logger.info("[Signal] EntryQualityFilter REJECTED #{index_cfg[:key]} #{final_direction}: " \
                            "#{quality_result[:reject_reason]} (score=#{quality_result[:score]})")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
        Rails.logger.info("[Signal] EntryQualityFilter PASSED #{index_cfg[:key]} #{final_direction} " \
                          "score=#{quality_result[:score]} #{quality_result[:breakdown]}")
        # ===== END ENTRY QUALITY FILTER =====

        permission = :exit_testing
        smc_decision = final_direction == :bullish ? :call : :put

        # ===== PERMISSION RESOLUTION (HARD) =====
        # Source-of-truth permission derived from SMC + AVRZ (deterministic).
        permission = Trading::PermissionResolver.resolve(symbol: index_cfg[:key], instrument: instrument)
        if permission == :blocked
          Rails.logger.info("[Signal] PermissionResolver BLOCKED #{index_cfg[:key]} - no trade")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
        # ===== END PERMISSION RESOLUTION =====

        # ===== SMC DECISION ALIGNMENT (HARD FILTER) =====
        # Check if SMC decision (call/put/no_trade) aligns with signal direction
        # This provides additional confirmation beyond permission levels
        # Skip this check if SMC+AVRZ permission system is disabled
        enable_smc_permission = signals_cfg.fetch(:enable_smc_avrz_permission, true)
        enable_smc_alignment = signals_cfg.fetch(:enable_smc_decision_alignment, true)

        if enable_smc_permission && enable_smc_alignment
          smc_decision = get_smc_decision(index_cfg, instrument, signals_cfg, final_direction)
          unless smc_decision_aligned?(smc_decision, final_direction)
            Rails.logger.info(
              "[Signal] SMC Decision BLOCKED #{index_cfg[:key]}: " \
              "signal=#{final_direction}, smc=#{smc_decision} (misaligned or no_trade)"
            )
            Signal::StateTracker.reset(index_cfg[:key])
            return
          end
          Rails.logger.info("[Signal] SMC Decision CONFIRMED #{index_cfg[:key]}: #{smc_decision} aligns with #{final_direction}")
        else
          Rails.logger.debug { "[Signal] SMC Decision alignment check SKIPPED for #{index_cfg[:key]} (SMC+AVRZ disabled)" }
          smc_decision = final_direction == :bullish ? :call : :put
        end
        # ===== END SMC DECISION ALIGNMENT =====

        # Get state snapshot first for signal persistence
        state_snapshot = Signal::StateTracker.record(
          index_key: index_cfg[:key],
          direction: final_direction,
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          config: signals_cfg
        )

        # 10. Options Analysis
        options_analysis = execute_options_analysis(
          index_cfg,
          instrument,
          final_direction,
          primary_series,
          effective_validation_mode,
          expiry_date: no_trade_gate[:expiry_date],
          chain_data: no_trade_gate[:chain_data]
        )

        # 11. Metadata Building
        diagnostic_metadata = build_diagnostic_metadata(
          index_cfg: index_cfg,
          final_direction: final_direction,
          primary_analysis: primary_analysis,
          regime: regime,
          options_analysis: options_analysis,
          validation_result: validation_result,
          state_snapshot: state_snapshot,
          effective_validation_mode: effective_validation_mode,
          signals_cfg: signals_cfg,
          primary_tf: primary_tf,
          effective_timeframe: effective_timeframe,
          smc_decision: smc_decision,
          permission: permission
        )

        # Build clear entry path identifier for tracking and analysis
        entry_path = build_entry_path_identifier(
          strategy_recommendation: strategy_recommendation,
          use_strategy_recommendations: use_strategy_recommendations,
          primary_tf: primary_tf,
          effective_timeframe: effective_timeframe,
          confirmation_tf: confirmation_tf,
          enable_confirmation: enable_confirmation
        )

        # Prepare enriched diagnostic diagnostic_metadata payload
        diagnostic_metadata = {
          # Market State Diagnostics
          regime: regime,
          regime_confidence: regime_result&.[](:confidence) || 0,
          regime_metrics: regime_result&.[](:metrics) || {},
          # Multi-Timeframe Diagnostics
          ta_signal: ta_result&.dig(:signal),
          ta_confidence: ta_result&.dig(:confidence),
          ta_bias: ta_result&.dig(:bias_summary, :summary, :bias),
          mtf_rsi: ta_result&.dig(:indicators)&.transform_values { |v| v[:rsi] },
          mtf_macd: ta_result&.dig(:indicators)&.transform_values { |v| v[:macd] },
          mtf_atr: ta_result&.dig(:indicators)&.transform_values { |v| v[:atr] },
          # Execution Context
          entry_path: entry_path,
          strategy: strategy_recommendation&.dig(:strategy_name) || 'supertrend_adx',
          strategy_mode: use_strategy_recommendations ? 'recommended' : 'supertrend_adx',
          primary_timeframe: primary_tf,
          effective_timeframe: effective_timeframe,
          confirmation_timeframe: confirmation_tf,
          confirmation_enabled: enable_confirmation,
          confirmation_direction: confirmation_analysis&.dig(:direction),
          validation_mode: signals_cfg[:validation_mode] || 'balanced',
          validation_passed: validation_result[:valid],
          state_count: state_snapshot[:count],
          state_multiplier: state_snapshot[:multiplier],
          original_timeframe: primary_tf,
          # SMC/Permission integration
          smc_decision: smc_decision.to_s,
          smc_permission: permission.to_s
        }

        signal = TradingSignal.create_from_analysis(
          index_key: index_cfg[:key],
          direction: final_direction.to_s,
          timeframe: effective_timeframe,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: confidence_score,
          metadata: diagnostic_metadata
        )

        # Rails.logger.info("[Signal] Signal state for #{index_cfg[:key]}: count=#{state_snapshot[:count]} multiplier=#{state_snapshot[:multiplier]}")

        # ===== EXIT IF BLOCKED BY OPTIONS BEHAVIOR =====
        if expiry_blocked
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          record_signal_skip(signal, 'expiry midday decay')
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        # ===== END OPTIONS BEHAVIOR ANALYSIS =====

        # ===== STRIKE QUALIFICATION LAYER (HARD GATE) =====
        # First point where we have:
        # - symbol (index_cfg[:key])
        # - side (from final_direction)
        # - permission (from PermissionResolver)
        # - option chain (fetched inside ChainAnalyzer)
        # - expected spot move (ATR-derived from series)
        expected_spot_move =
          begin
            atr = primary_series.atr(14)
            atr&.to_f
          rescue StandardError
            nil
          end

        unless expected_spot_move&.positive?
          Rails.logger.info("[Signal] Missing expected_spot_move (ATR) -> BLOCK #{index_cfg[:key]}")
          record_signal_skip(signal, 'missing ATR')
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        picks = Options::ChainAnalyzer.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: final_direction,
          permission: permission,
          expected_spot_move: expected_spot_move
        )
        # ===== END STRIKE QUALIFICATION LAYER =====

        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{final_direction}")
          record_signal_skip(signal, 'no suitable strikes')
          return
        end

        Rails.logger.info("[Signal] Found #{picks.size} option picks for #{index_cfg[:key]}: #{picks.pluck(:symbol).join(', ')}")

        market_context_extra, mc_gate_blocked = evaluate_market_context_for_entry(
          index_cfg: index_cfg,
          primary_series: primary_series,
          expiry_date: expiry_date,
          chain_data: chain_data,
          final_direction: final_direction,
          pick: picks.first,
          smc_decision: smc_decision
        )
        if mc_gate_blocked
          record_signal_skip(signal, 'market context gate')
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        # Prepare entry metadata to pass to EntryGuard
        entry_metadata = diagnostic_metadata.merge(
          entry_contract: supertrend_direct_entry ? 'supertrend_machine_v1' : 'bos_machine_v1',
          permission: execution_permission,
          entry_quality_score: quality_result[:score],
          entry_quality_breakdown: quality_result[:breakdown]
        )

        Entries::BosEntryEngine.run_for(
          index_cfg: index_cfg,
          instrument: instrument,
          direction: final_direction,
          picks: picks,
          entry_metadata: entry_metadata,
          permission: permission
        )

        # Rails.logger.info("[Signal] Completed analysis for #{index_cfg[:key]}")
      rescue Exception => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%Q{\n})}")
        Rails.logger.error("[Signal] #{index_cfg[:key]} #{e.class} #{e.message}")
        summary&.block!("error")
        summary
      ensure
        Thread.current[:signal_cycle_summary] = nil
      end

      private

      def tradable_session?(index_cfg)
        if TradingSession::Service.market_closed?
          Rails.logger.debug { "[Signal] Market closed - skipping analysis for #{index_cfg[:key]}" }
          return false
        end

        # Rails.logger.info("[Signal] Fetched #{series.candles.size} candles for #{index_cfg[:key]} @ #{timeframe}")
        # Rails.logger.debug { "[Signal] Adaptive Supertrend config: #{supertrend_cfg}" }

        # [DYNAMIC CONFIG] Use optimized parameters if available
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        supertrend_cfg = resolved_supertrend_cfg(instrument, interval, signals_cfg)
        st_service = Indicators::Supertrend.new(series: series, **supertrend_cfg)
        st = st_service.call
        st[:adaptive_multipliers]&.compact&.last
        # Rails.logger.info(
        #   "[Signal] Supertrend(#{timeframe}) for #{index_cfg[:key]}: trend=#{st[:trend]} last_value=#{st[:last_value]} multiplier=#{last_multiplier}"
        # )

        # [DYNAMIC CONFIG] Use optimized ADX strength if available
        adx_min = resolved_adx_min(instrument, interval, index_cfg, timeframe)
        adx_value = instrument.adx(14, interval: interval)
        # Rails.logger.info("[Signal] ADX(#{timeframe}) for #{index_cfg[:key]}: #{adx_value}")

        direction = decide_direction(
          st,
          adx_value,
          min_strength: adx_min,
          timeframe_label: timeframe
        )
        true
      end

        {
          status: :ok,
          series: series,
          supertrend: st,
          adx_value: adx_value,
          direction: direction,
          last_candle_timestamp: series.candles.last&.timestamp
        }
      rescue Exception => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%Q{\n})}")
        Rails.logger.error("[Signal] Timeframe analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      def initialize_analysis_context(signals_cfg)
        entry_primary = (signals_cfg.dig(:entry_strategy, :primary) || signals_cfg[:entry_strategy].to_s).to_s.strip.downcase

        primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, true)
        confirmation_tf = (signals_cfg[:confirmation_timeframe].to_s if enable_confirmation && signals_cfg[:confirmation_tf].present?)

        # supertrend_cfg = signals_cfg[:supertrend] # No longer needed here, resolved in analyze_timeframe
        # unless supertrend_cfg
        #   Rails.logger.error("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
        #   return { status: :error, message: 'Supertrend configuration missing' }
        # end

        # adx_cfg = signals_cfg[:adx] || {} # No longer needed here, resolved in analyze_timeframe
        # enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, true)
        # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
        # adx_min_strength = enable_adx_filter ? adx_cfg[:min_strength] : 0 # No longer needed here, resolved in analyze_timeframe

        # Analyze primary timeframe
        primary_analysis = analyze_timeframe(
          index_cfg: index_cfg,
          instrument: instrument,
          timeframe: primary_tf
          # supertrend_cfg: supertrend_cfg, # Removed
          # adx_min_strength: adx_min_strength # Removed
        )
        if trend_direction == :none
          Rails.logger.info("[Signal] SupertrendTrend :none — no trade for #{index_cfg[:key]}")
          Signal::StateTracker.reset(index_cfg[:key])
          record_cycle_block!("supertrend_none")
          return
        end

        primary_direction = primary_analysis[:direction]
        confirmation_analysis = nil
        confirmation_direction = nil

        if confirmation_tf.present?
          # Only apply ADX filter if enabled, otherwise use 0 to bypass filter
          # confirmation_adx_min = if enable_adx_filter # No longer needed here, resolved in analyze_timeframe
          #                          adx_cfg[:confirmation_min_strength] || adx_cfg[:min_strength]
          #                        else
          #                          0
          #                        end

          confirmation_analysis = analyze_timeframe(
            index_cfg: index_cfg,
            instrument: instrument,
            timeframe: confirmation_tf
            # supertrend_cfg: supertrend_cfg, # Removed
            # adx_min_strength: confirmation_adx_min # Removed
          )
        end

        validation_result = comprehensive_validation(
          index_cfg, final_direction, primary_series,
          primary_analysis[:supertrend], { value: primary_analysis[:adx_value] },
          supertrend_only: true,
          validation_mode: effective_validation_mode
        )

        ta_result = perform_diagnostic_ta(index_cfg, signals_cfg)

        {
          direction: final_direction,
          primary_analysis: primary_analysis,
          confirmation_analysis: nil,
          primary_series: primary_series,
          ta_result: ta_result,
          regime_result: regime_result,
          regime: regime_result[:regime],
          validation_result: validation_result,
          effective_validation_mode: effective_validation_mode
        }
      rescue Exception => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%Q{\n})}")
        Rails.logger.error("[Signal] Multi-timeframe analysis failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      def perform_diagnostic_ta(index_cfg, signals_cfg)
        ta_timeframes = signals_cfg[:ta_timeframes] || [5, 15, 60]
        ta_days_back = signals_cfg[:ta_days_back] || 30
        index_symbol = index_cfg[:key].to_s.downcase.to_sym
        ta_analyzer = IndexTechnicalAnalyzer.new(index_symbol)
        ta_analysis = ta_analyzer.call(timeframes: ta_timeframes, days_back: ta_days_back)
        ta_analysis[:success] ? ta_analyzer.result : nil
      end

      def execute_standard_analysis_flow(index_cfg, instrument, signals_cfg, primary_tf, confirmation_tf)
        # 1. Index TA Step
        ta_result = perform_standard_ta(index_cfg, signals_cfg)
        return unless ta_result || !signals_cfg.fetch(:enable_index_ta_filter, false)

        # 2. Strategy Recommendation
        strategy_recommendation = resolve_strategy_recommendation(index_cfg, signals_cfg, primary_tf)
        effective_timeframe = strategy_recommendation[:effective_timeframe]

        # 3. Analyze Timeframes
        analysis = analyze_primary_and_confirmation(
          index_cfg: index_cfg,
          instrument: instrument,
          signals_cfg: signals_cfg,
          primary_tf: primary_tf,
          effective_timeframe: effective_timeframe,
          confirmation_tf: confirmation_tf,
          strategy_recommendation: strategy_recommendation[:recommendation]
        )
        return unless analysis

        final_direction = analysis[:final_direction]
        primary_series = analysis[:primary_analysis][:series]

        # 4. Regime and Validation
        regime_result = MarketRegimeDetector.new(primary_series).detect
        regime = regime_result[:regime]

        effective_validation_mode = if %w[RANGING CHOPPY].include?(regime.to_s)
                                      'conservative'
                                    else
                                      (signals_cfg[:validation_mode] || 'balanced').to_s
                                    end
        if %w[RANGING CHOPPY].include?(regime.to_s)
          Rails.logger.info("[Signal] Switching to CONSERVATIVE validation for #{index_cfg[:key]} due to #{regime} regime")
        end

        if direction_gate_blocked?(index_cfg, signals_cfg, final_direction, regime)
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

      # Comprehensive validation checks before proceeding with trades
      # When supertrend_only: true, ADX and trend_confirmation are skipped (Supertrend-only entry).
      def comprehensive_validation(index_cfg, direction, series, supertrend_result, adx, supertrend_only: false)
        mode_config = get_validation_mode_config
        # Rails.logger.info("[Signal] Running comprehensive validation for #{index_cfg[:key]} #{direction} (mode: #{mode_config[:mode]})")

        {
          direction: final_direction,
          primary_analysis: analysis[:primary_analysis],
          confirmation_analysis: analysis[:confirmation_analysis],
          primary_series: primary_series,
          ta_result: ta_result,
          regime_result: regime_result,
          regime: regime_result[:regime],
          validation_result: validation_result,
          effective_validation_mode: effective_validation_mode,
          effective_timeframe: effective_timeframe,
          strategy_recommendation: strategy_recommendation[:recommendation],
          use_strategy_recommendations: signals_cfg.fetch(:use_strategy_recommendations, false)
        }
      end

      def perform_standard_ta(index_cfg, signals_cfg)
        enable_index_ta_filter = signals_cfg.fetch(:enable_index_ta_filter, false)
        ta_min_confidence = signals_cfg[:ta_min_confidence] || 0.6
        ta_timeframes = signals_cfg[:ta_timeframes] || [5, 15, 60]
        ta_days_back = signals_cfg[:ta_days_back] || 30

        index_symbol = index_cfg[:key].to_s.downcase.to_sym
        ta_analyzer = IndexTechnicalAnalyzer.new(index_symbol)
        ta_analysis = ta_analyzer.call(timeframes: ta_timeframes, days_back: ta_days_back)

        if ta_analysis[:success] && ta_analyzer.success?
          result = ta_analyzer.result
          Rails.logger.info(
            "[Signal] Index TA for #{index_cfg[:key]}: signal=#{result[:signal]}, " \
            "confidence=#{result[:confidence].round(2)}, bias=#{result.dig(:bias_summary, :summary, :bias)}"
          )

          if enable_index_ta_filter && (result[:signal] == :neutral || result[:confidence] < ta_min_confidence)
            Rails.logger.info(
              "[Signal] Skipping signal generation for #{index_cfg[:key]} (TA Filter ACTIVE): " \
              "TA signal=#{result[:signal]}, confidence=#{result[:confidence].round(2)}"
            )
            return nil
          end
          result
        else
          Rails.logger.warn("[Signal] Index TA failed for #{index_cfg[:key]}: #{ta_analyzer.error}")
          nil
        end
      end

        # 3. Enhanced ADX Confirmation - Ensure strong trend (if enabled); skipped when supertrend_only
        unless supertrend_only
          signals_cfg = AlgoConfig.fetch[:signals] || {}
          enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, true)
          if enable_adx_filter
            adx_result = validate_adx_strength(adx, supertrend_result, mode_config)
            validation_checks << adx_result
          else
            # Rails.logger.debug('[Signal] ADX validation skipped (filter disabled)')
            validation_checks << { valid: true, name: 'ADX Strength', message: 'ADX filter disabled' }
          end
        end

        # 4. Trend Confirmation - Multiple signal validation (if enabled); skipped when supertrend_only
        if !supertrend_only && mode_config[:require_trend_confirmation]
          trend_result = validate_trend_confirmation(supertrend_result, series)
          validation_checks << trend_result
        end

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        supertrend_cfg = resolved_supertrend_cfg(instrument, interval, signals_cfg)
        st = Indicators::Supertrend.new(series: series, **supertrend_cfg).call

        adx_min = resolved_adx_min(instrument, interval, index_cfg, timeframe)
        adx_value = instrument.adx(14, interval: interval)
        direction = decide_direction(
          st,
          adx_value,
          min_strength: adx_min_strength.positive? ? adx_min_strength : adx_min,
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
        Rails.logger.error(
          "[Signal] Timeframe analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}"
        )
        { status: :error, message: e.message }
      end

      def normalize_interval(timeframe)
        return if timeframe.blank?

        cleaned = timeframe.to_s.strip.downcase
        digits = cleaned.gsub(/[^0-9]/, "")
        digits.presence
      end

      def decide_direction(supertrend_result, adx_value, min_strength:, timeframe_label:)
        min_required = min_strength.to_f
        adx_numeric = adx_value.to_f

        if min_required.positive? && adx_numeric < min_required
          return :avoid
        end

        if supertrend_result.blank? || supertrend_result[:trend].nil?
          Rails.logger.warn("[Signal] Supertrend result invalid on #{timeframe_label}: #{supertrend_result}")
          return :avoid
        end

        case supertrend_result[:trend]
        when :bullish then :bullish
        when :bearish then :bearish
        else :avoid
        end
      end

        # 5. Market Timing Check - Avoid problematic times (always required)
        timing_result = validate_market_timing
        validation_checks << timing_result

        # Log all validation results
        # Rails.logger.info("[Signal] Validation Results (#{mode_config[:mode]} mode):")
        validation_checks.each do |check|
          _status = check[:valid] ? '✅' : '❌'
          # Rails.logger.info("  #{_status} #{check[:name]}: #{check[:message]}")
        end

        histogram = result.dig(:value, :histogram).to_f
        return 0.10 if direction == :bullish && histogram.positive?
        return 0.10 if direction == :bearish && histogram.negative?

        if failed_checks.empty?
          # Rails.logger.info("[Signal] All validation checks passed for #{index_cfg[:key]} (#{mode_config[:mode]} mode)")
          { valid: true, reason: 'All checks passed' }
        else
          failed_reasons = failed_checks.pluck(:name).join(', ')
          failed_messages = failed_checks.map { |check| "#{check[:name]}: #{check[:message]}" }.join('; ')
          { valid: false, reason: "Failed checks: #{failed_reasons} (#{failed_messages})" }
        end
      end

      # Get validation mode configuration
      def get_validation_mode_config
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        mode = signals_cfg[:validation_mode] || 'balanced'
        mode_config = signals_cfg.dig(:validation_modes, mode.to_sym) ||
                      signals_cfg.dig(:validation_modes, :balanced) || {}

        # Ensure mode_config is always a Hash (handle edge cases where config might be wrong type)
        mode_config = {} unless mode_config.is_a?(Hash)

        0.0
      rescue StandardError => e
        Rails.logger.debug("[Signal::Engine] SMC bias factor error: #{e.message}")
        0.0
      end

      # Validate IV Rank - avoid extreme volatility conditions
      def validate_iv_rank(_index_cfg, series, mode_config = nil)
        if mode_config.nil? || mode_config.is_a?(String) || mode_config.is_a?(Symbol)
          mode_config = get_validation_mode_config(override_mode: mode_config)
        end

        unless mode_config.is_a?(Hash)
          Rails.logger.error("[Signal] CRITICAL: mode_config is #{mode_config.class} (#{mode_config.inspect}) in validate_iv_rank")
          # Force it to be a valid hash to prevent crash
          mode_config = get_validation_mode_config
        end

        # For now, we'll use a simple volatility check based on recent price movement
        # In a full implementation, you'd calculate actual IV rank from historical IV data

        candles = series.candles
        if candles.blank? || candles.size < 5
          return { valid: false, name: 'IV Rank', message: 'Insufficient data for volatility assessment' }
        end

        unless mode_config.is_a?(Hash)
          Rails.logger.error("[Signal] CRITICAL: mode_config is #{mode_config.class} (#{mode_config.inspect}) in validate_iv_rank")
          # Force it to be a valid hash to prevent crash
          mode_config = get_validation_mode_config
        end

        decision = Smc::BiasEngine.new(instrument).decision
        case decision
        when :call then :bullish
        when :put then :bearish
        else :neutral
        end
      rescue StandardError
        :neutral
      end

      # Validate theta risk - avoid high theta decay situations
      def validate_theta_risk(_index_cfg, _direction, mode_config = nil)
        if mode_config.nil? || mode_config.is_a?(String) || mode_config.is_a?(Symbol)
          mode_config = get_validation_mode_config(override_mode: mode_config)
        end

        current_time = Time.zone.now
        hour = current_time.hour
        minute = current_time.min

        direction = primary_analysis[:direction]
        series = primary_analysis[:series]
        macd_factor = series && direction ? macd_confidence_factor(direction, series) : 0.0
        smc_factor = index_cfg && direction ? smc_bias_confidence_factor(direction, index_cfg) : 0.0

        capped = [base_confidence + adx_factor + validation_factor + supertrend_factor + macd_factor + smc_factor, 1.0].min
        return capped if validation_result[:valid]

      # Enhanced ADX validation with trend strength assessment
      def validate_adx_strength(index_cfg, adx, _supertrend_result, mode_config = nil)
        mode_config ||= get_validation_mode_config

        adx_value = adx[:value].to_f
        # 1. Check per-index override
        # 2. Check mode config (e.g., balanced/strict)
        # 3. Check global signals default
        min_strength =
          index_cfg.dig(:adx_thresholds, :primary_min_strength) ||
          mode_config[:adx_min_strength] ||
          AlgoConfig.fetch.dig(:signals, :adx, :min_strength).to_f

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

      def adx_confidence_factor(adx_value)
        return 0.0 unless adx_value

        case adx_value.to_f
        when 30.. then 0.3
        when 20...30 then 0.2
        when 15...20 then 0.1
        else 0.0
        end
      end

      def supertrend_confidence_factor(supertrend)
        return 0.0 unless supertrend&.dig(:last_value)

        st_value = supertrend[:last_value].to_f
        [st_value / 1000.0, 0.1].min
      end

      # Validate market timing - avoid problematic trading times.
      # Uses IST via TradingSession so behavior matches market_closed? and entry_allowed?
      def validate_market_timing
        unless Market::Calendar.trading_day_today?
          return { valid: false, name: 'Market Timing', message: 'Not a trading day (weekend/holiday)' }
        end

        current_ist = TradingSession::Service.current_ist_time
        hour = current_ist.hour
        minute = current_ist.min

        # Market hours: 9:15 AM to 3:30 PM IST
        market_open = hour > 9 || (hour == 9 && minute >= 15)
        market_close = hour > 15 || (hour == 15 && minute >= 30)

        if !market_open
          { valid: false, name: 'Market Timing', message: 'Market not yet open' }
        elsif market_close
          { valid: false, name: 'Market Timing', message: 'Market closed' }
        else
          # Check for session blackouts (Loss Avoidance)
          restrictions = AlgoConfig.fetch[:trading_time_restrictions]
          if restrictions&.[](:enabled) && restrictions[:avoid_periods].present?
            current_hm = current_ist.strftime('%H:%M')
            restrictions[:avoid_periods].each do |period|
              start_time, end_time = period.split('-')
              if current_hm >= start_time && current_hm < end_time
                return { valid: false, name: 'Market Timing', message: "Loss Avoidance: Blocked during non-profitable session (#{period})" }
              end
            end
          end

          if hour == 9 && minute < 30
            { valid: true, name: 'Market Timing', message: 'Early market - high volatility period' }
          elsif hour >= 14 && minute >= 30
            { valid: true, name: 'Market Timing', message: 'Late market - theta decay risk' }
          else
            { valid: true, name: 'Market Timing', message: 'Normal trading hours' }
          end
        end
      end

      # RSI anti-chase gate — blocks CE entries when overbought, PE entries when oversold.
      # Does NOT interfere with the normal trending RSI zone (45–75 CE, 25–55 PE).
      def validate_rsi_gate(direction, series, mode_config)
        return { valid: true } unless mode_config[:require_rsi_check]

        rsi_val = Indicators::RsiIndicator.new(series: series).rsi_value_at(-1)
        return { valid: true, note: 'RSI unavailable' } if rsi_val.nil?

        rsi_val = rsi_val.to_f

        if direction == :bullish && rsi_val > mode_config.fetch(:rsi_overbought_block, 78).to_f
          return { valid: false, reason: "RSI overbought (#{rsi_val.round(1)}) — avoid chasing CE entry", check: :rsi_overbought }
        end

        if direction == :bearish && rsi_val < mode_config.fetch(:rsi_oversold_block, 22).to_f
          return { valid: false, reason: "RSI oversold (#{rsi_val.round(1)}) — avoid chasing PE entry", check: :rsi_oversold }
        end

        { valid: true, rsi_value: rsi_val }
      rescue StandardError => e
        Rails.logger.warn("[Signal::Engine] RSI gate error — allowing through: #{e.message}")
        { valid: true }
      end

      # EMA direction tie-break: if Supertrend and EMA 9/21 disagree,
      # require ADX >= 25 to proceed (strong momentum overrides cross-current).
      def check_ema_direction_alignment(direction, series, adx_value)
        ema_result    = Indicators::EmaDirectionIndicator.new(series: series).calculate
        ema_direction = ema_result[:direction]

        if ema_direction == :neutral || ema_direction == direction
          return { aligned: true, adx_override_needed: false, ema_direction: ema_direction }
        end

        adx_override_threshold = 25.0
        if adx_value.to_f >= adx_override_threshold
          return { aligned: true, adx_override_needed: false, ema_direction: ema_direction,
                   note: 'EMA disagreement overridden by ADX strength' }
        end

        { aligned: false, adx_override_needed: true, ema_direction: ema_direction,
          required_adx: adx_override_threshold, actual_adx: adx_value }
      rescue StandardError => e
        Rails.logger.debug("[Signal::Engine] EMA alignment check error: #{e.message}")
        { aligned: true, adx_override_needed: false }
      end

      # SMC Discount/Premium zone filter:
      # CE (bullish): ideal in discount; blocked in premium unless ADX >= zone_filter_adx_override.
      # PE (bearish): ideal in premium; blocked in discount unless ADX >= zone_filter_adx_override.
      def smc_zone_allows_entry?(direction, index_cfg, adx_value)
        zone = get_smc_zone(index_cfg)
        return true if zone == :equilibrium

        zone_override_adx = AlgoConfig.fetch.dig(:signals, :smc, :zone_filter_adx_override).to_f rescue 30.0

        if direction == :bullish && zone == :premium
          return adx_value.to_f >= zone_override_adx
        end

        if direction == :bearish && zone == :discount
          return adx_value.to_f >= zone_override_adx
        end

        true
      rescue StandardError => e
        Rails.logger.error("[Signal] ExpiryModel unavailable (#{e.class}: #{e.message}); allowing trade")
        true
      end

      def resolve_nearest_expiry_date(index_cfg:)
        Options::DerivativeChainAnalyzer.new(index_key: index_cfg[:key]).nearest_expiry
      rescue StandardError => e
        Rails.logger.warn("[Signal] resolve_nearest_expiry_date #{index_cfg[:key]}: #{e.class} — #{e.message}")
        nil
      end

      def entry_dte_guard_blocks?(index_cfg:, signals_cfg:, nearest_expiry:)
        cfg = signals_cfg[:entry_dte_guard] || {}
        return false unless cfg[:enabled]

        threshold = cfg.fetch(:reject_when_days_to_expiry_lte, 1).to_i
        return false if nearest_expiry.blank?

        today = Time.zone.today
        expiry_day = nearest_expiry.is_a?(Date) ? nearest_expiry : Date.parse(nearest_expiry.to_s)
        dte = (expiry_day - today).to_i
        if dte <= threshold
          Rails.logger.info("[Signal] entry_dte_guard BLOCKED #{index_cfg[:key]}: DTE=#{dte} (<= #{threshold})")
          return true
        end

        false
      rescue ArgumentError, TypeError => e
        Rails.logger.warn("[Signal] entry_dte_guard parse error #{index_cfg[:key]}: #{e.message}")
        false
      end

      def execute_options_analysis(index_cfg, expiry_date:, expiry_blocked:)
        {
          gamma_pressure: { score: 0.0, strike: nil },
          iv_rank: { valid: true },
          theta_risk: { valid: true },
          expiry_blocked: expiry_blocked,
          expiry_date: expiry_date,
          chain_data: nil
        }
      end

      def build_diagnostic_metadata(index_cfg:, final_direction:, primary_analysis:, regime:, options_analysis:,
                                    validation_result:, state_snapshot:, effective_validation_mode:,
                                    signals_cfg:, primary_tf:, effective_timeframe:, smc_decision:, permission:)
        Signal::MetadataBuilder.build(
          index_cfg: index_cfg,
          final_direction: final_direction,
          primary_analysis: primary_analysis,
          confirmation_analysis: nil,
          regime: regime,
          regime_result: { regime: regime },
          ta_result: nil,
          options_analysis: options_analysis,
          validation_result: validation_result,
          state_snapshot: state_snapshot,
          effective_validation_mode: effective_validation_mode,
          signals_cfg: signals_cfg,
          primary_tf: primary_tf,
          effective_timeframe: effective_timeframe,
          confirmation_tf: nil,
          enable_confirmation: false,
          smc_decision: smc_decision,
          permission: permission,
          smc_confluence_ltf_summary: nil,
          strategy_name: "supertrend",
          strategy_mode: "stock"
        )
      end

      def record_signal_skip(signal, reason, stage: nil, code: nil)
        extra = {}
        extra["entry_skip_stage"] = stage.to_s if stage.present?
        extra["entry_skip_code"] = code.to_s if code.present?
        signal&.record_entry_outcome("skipped", reason, extra_metadata: extra.presence)
      end

      def execute_stock_entry_gate(index_cfg:, signal:, final_direction:, options_analysis:, permission:)
        if options_analysis[:expiry_blocked]
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          record_signal_skip(
            signal,
            "expiry_midday_decay: Midday decay period blocked entry for this expiry",
            stage: "expiry_model",
            code: "expiry_midday_decay"
          )
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: final_direction)
        if picks.blank?
          skip_reason = "No ATM option strike available"
          Rails.logger.warn("[Signal] #{skip_reason} for #{index_cfg[:key]} #{final_direction}")
          record_signal_skip(signal, skip_reason, stage: "strike_selection", code: "no_strikes")
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        Rails.logger.info("[Signal] Stock strike pick #{index_cfg[:key]}: #{picks.pluck(:symbol).join(', ')}")
        { picks: picks, execution_permission: permission }
      end

      def trigger_entry_flow(index_cfg:, signal:, picks:, final_direction:, primary_series:, primary_tf:,
                             diagnostic_metadata:, quality_result:, execution_permission:)
        entry_metadata = diagnostic_metadata.merge(
          entry_contract: Entries::EntryGuard::SUPERTREND_CONTRACT,
          permission: execution_permission,
          entry_quality_score: quality_result[:score],
          entry_quality_breakdown: quality_result[:breakdown],
          fast_entry_mode: FastEntryMode.enabled?,
          bos_id: "st_#{index_cfg[:key]}_#{Time.current.to_i}",
          bos_timeframe: primary_tf,
          bos_origin_price: primary_series.candles.last&.close,
          bos_level: primary_series.candles.last&.close,
          entry_underlying_price: primary_series.candles.last&.close
        )

        Rails.logger.debug series.candles.last
        Rails.logger.debug series.candles.first
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
        false
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
      rescue Exception => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%Q{\n})}")
        Rails.logger.error("[Signal] Strategy-based analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      # Build clear entry path identifier for tracking
      # Format: "strategy_timeframe_confirmation" e.g., "recommended_5m_none" or "supertrend_adx_1m_5m"
      def build_entry_path_identifier(strategy_recommendation:, use_strategy_recommendations:, primary_tf:, # rubocop:disable Lint/UnusedMethodArgument
                                      effective_timeframe:, confirmation_tf:, enable_confirmation:)
        strategy_part = if use_strategy_recommendations && strategy_recommendation&.dig(:recommended)
                          strategy_recommendation[:strategy_name].downcase.gsub(/\s+/, '_')
                        else
                          'supertrend_adx'
                        end

        timeframe_part = effective_timeframe

        confirmation_part = if enable_confirmation && confirmation_tf.present?
                              confirmation_tf
                            else
                              'none'
                            end

        "#{strategy_part}_#{timeframe_part}_#{confirmation_part}"
      end

      def decide_direction(supertrend_result, adx_value, min_strength:, timeframe_label:)
        min_required = min_strength.to_f
        adx_numeric = adx_value.to_f

        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :supertrend).first
        return base_cfg unless optimized&.params.is_a?(Hash)

        trend = supertrend_result[:trend]
        # Rails.logger.debug { "[Signal] Supertrend trend(#{timeframe_label}): #{trend}" }

        # Use the trend from Supertrend calculation
        # NOTE: Enhanced direction validation happens later via DirectionValidator
        # This method provides initial direction filter only
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

      def resolved_adx_min(instrument, interval, index_cfg, timeframe_label)
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        adx_cfg = signals_cfg[:adx] || {}
        static_min = index_cfg.dig(:adx_thresholds, timeframe_label.to_sym) || adx_cfg[:min_strength] || 0

        return static_min unless dynamic_config_enabled?

        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :adx).first
        return static_min unless optimized&.params.is_a?(Hash)

        optimized_min = optimized.params.symbolize_keys[:min_strength]
        optimized_min || static_min
      end

      # Get SMC decision (call/put/no_trade) for signal alignment check
      def get_smc_decision(index_cfg, instrument, signals_cfg, signal_direction)
        # Check if SMC decision alignment is enabled
        enable_smc_alignment = signals_cfg.fetch(:enable_smc_decision_alignment, true)
        # Return permissive default based on signal direction when disabled
        unless enable_smc_alignment
          return signal_direction == :bullish ? :call : :put
        end

        begin
          # Use BiasEngine to get SMC decision
          # Note: We use delay_seconds: 0 since we're already in a signal generation context
          # and don't want to add unnecessary delays
          engine = Smc::BiasEngine.new(instrument, delay_seconds: 0)
          decision = engine.decision

          # If BiasEngine returns :no_trade, be permissive and align with signal direction
          if decision == :no_trade
            Rails.logger.debug { "[Signal] SMC decision returned :no_trade for #{index_cfg[:key]}, defaulting to signal direction" }
            return signal_direction == :bullish ? :call : :put
          end

          decision
        rescue Exception => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%Q{\n})}")
          Rails.logger.warn("[Signal] SMC decision check failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
          # Default to signal direction on error (allows trades instead of blocking)
          # :call for bullish signals, :put for bearish signals
          signal_direction == :bullish ? :call : :put
        end
      end

      # Check if SMC decision aligns with signal direction
      # call = bullish, put = bearish, no_trade = blocks all
      def smc_decision_aligned?(smc_decision, signal_direction)
        return false if smc_decision.nil?
        return false if smc_decision == :no_trade

        case signal_direction
        when :bullish
          smc_decision == :call
        when :bearish
          smc_decision == :put
        else
          false
        end
      end

      def expiry_trade_allowed?(symbol)
        expiry_model = "Strategies::ExpiryModel".safe_constantize
        return true unless expiry_model

        expiry_model.trade_allowed?(symbol: symbol)
      rescue StandardError => e
        Rails.logger.error("[Signal] ExpiryModel unavailable (#{e.class}: #{e.message}); allowing trade")
        true
      end

      def resolve_nearest_expiry_date(index_cfg:, no_trade_gate:)
        exp = no_trade_gate&.dig(:expiry_date)
        return exp if exp.present?

        Options::DerivativeChainAnalyzer.new(index_key: index_cfg[:key]).nearest_expiry
      rescue StandardError => e
        Rails.logger.warn("[Signal] resolve_nearest_expiry_date #{index_cfg[:key]}: #{e.class} — #{e.message}")
        nil
      end

      def entry_dte_guard_blocks?(index_cfg:, signals_cfg:, nearest_expiry:)
        cfg = signals_cfg[:entry_dte_guard] || {}
        return false unless cfg[:enabled]

        threshold = cfg.fetch(:reject_when_days_to_expiry_lte, 1).to_i
        return false if nearest_expiry.blank?

        today = Time.zone.today
        expiry_day = nearest_expiry.is_a?(Date) ? nearest_expiry : Date.parse(nearest_expiry.to_s)
        dte = (expiry_day - today).to_i
        if dte <= threshold
          Rails.logger.info("[Signal] entry_dte_guard BLOCKED #{index_cfg[:key]}: DTE=#{dte} (<= #{threshold})")
          return true
        end

        false
      rescue ArgumentError, TypeError => e
        Rails.logger.warn("[Signal] entry_dte_guard parse error #{index_cfg[:key]}: #{e.message}")
        false
      end

      # MarketContext regime snapshot + optional hard gate (config: market_context.*).
      # @return [Array(Hash, Boolean, String, nil)] extra, blocked, block_detail when blocked
      def evaluate_market_context_for_entry(index_cfg:, primary_series:, expiry_date:, chain_data:,
                                            final_direction:, pick:, smc_decision: nil)
        return [{}, false] unless AlgoConfig.fetch.dig(:market_context, :enabled) == true

        snapshot = MarketContext::RegimeComposer.new(series: primary_series, index_key: index_cfg[:key]).call
        chain_signal = Options::ChainSignalExtractor.new(
          index_key: index_cfg[:key],
          expiry_date: expiry_date,
          chain_data: chain_data,
          final_direction: final_direction,
          atm_strike: pick[:strike]
        ).call
        profile = Trading::StrategyProfileSelector.select(snapshot)

        extra = {
          strategy_profile: profile,
          market_context_structure: snapshot.structure,
          market_context_strength: snapshot.strength,
          market_context_volatility: snapshot.volatility_state,
          market_context_participation: snapshot.participation,
          market_context_conviction: snapshot.conviction_score,
          market_context_displacement: snapshot.displacement,
          market_context_legacy_regime: snapshot.legacy_regime,
          chain_direction_confidence: chain_signal.direction_confidence,
          chain_direction_hint: chain_signal.direction_hint.to_s,
          chain_oi_confirmation: chain_signal.oi_confirmation,
          chain_premium_expansion: chain_signal.premium_expansion,
          chain_pcr: chain_signal.pcr
        }

        return [extra, false, nil] unless AlgoConfig.fetch.dig(:market_context, :gate, :enabled) == true

        gate = Trading::MarketPermissionGate.new(
          snapshot: snapshot,
          chain_signal: chain_signal,
          final_direction: final_direction,
          smc_decision: smc_decision
        ).call
        return [extra, false, nil] if gate.allowed

        block_detail = "#{gate.code}: #{gate.reason}".strip
        Observability::StructuredLog.info(
          event: 'entry_blocked',
          payload: {
            service: 'Signal::Engine',
            index_key: index_cfg[:key].to_s,
            stage: 'market_permission_gate',
            reason: gate.reason.to_s,
            code: gate.code.to_s
          }
        )
        Rails.logger.info("[Signal] MarketPermissionGate BLOCKED #{index_cfg[:key]}: #{gate.reason}")
        [extra, true, block_detail]
      rescue StandardError => e
        Rails.logger.error("[Signal] Market context evaluation failed: #{e.class} - #{e.message}")
        [{}, false, nil]
      end

      # --- Dynamic Configuration Helpers ---

      def dynamic_config_enabled?
        AlgoConfig.fetch.dig(:signals, :use_optimized_params) != false
      end

      def resolved_supertrend_cfg(instrument, interval, signals_cfg)
        base_cfg = (signals_cfg[:supertrend] || { period: 7, multiplier: 3.0 }).dup

        return base_cfg unless dynamic_config_enabled?

        # Try to find optimized params for this specific instrument + interval
        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :supertrend).first
        return base_cfg unless optimized && optimized.params.is_a?(Hash)

        # Map optimized keys (atr_period, multiplier) to service keys (period, base_multiplier)
        params = optimized.params.symbolize_keys
        base_cfg[:period] = params[:atr_period] if params[:atr_period]
        base_cfg[:base_multiplier] = params[:multiplier] if params[:multiplier]

        Rails.logger.info("[Signal] 🚀 Using optimized Supertrend for #{instrument.symbol_name} @ #{interval}: #{base_cfg}")
        base_cfg
      end

      def resolved_adx_min(instrument, interval, index_cfg, timeframe_label)
        static_min = index_cfg.dig(:adx_thresholds, timeframe_label == 'primary' ? :primary_min_strength : :confirmation_min_strength) || 15

        return static_min unless dynamic_config_enabled?

        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :adx).first
        return static_min unless optimized && optimized.params.is_a?(Hash)

        optimized_min = optimized.params.symbolize_keys[:min_strength]
        return static_min unless optimized_min

        Rails.logger.info("[Signal] 🚀 Using optimized ADX min for #{instrument.symbol_name} @ #{interval}: #{optimized_min}")
        optimized_min
      end

      def record_signal_skip(signal, reason, stage: nil, code: nil)
        extra = {}
        extra['entry_skip_stage'] = stage.to_s if stage.present?
        extra['entry_skip_code'] = code.to_s if code.present?
        signal&.record_entry_outcome('skipped', reason, extra_metadata: extra.presence)
      end

      # =====================================================================
      # Pipeline stage methods extracted from run_for
      # =====================================================================

      def trading_context_blocked?(index_cfg, primary_series, primary_analysis, regime_result, regime_state, signals_cfg)
        return false unless signals_cfg.fetch(:enable_trading_context_gate, true)
        return false unless regime_state

        indicators = {
          adx_value: primary_analysis[:adx_value],
          regime_confidence: regime_result&.[](:confidence)
        }
        context = Context::Builder.call(
          market: primary_series,
          indicators: indicators,
          regime_state: regime_state,
          index_key: index_cfg[:key],
          strictness: signals_cfg.fetch(:trading_context_strictness, :strict)
        )
        unless context.tradable?
          Rails.logger.info(
            "[Signal] TradingContext BLOCKED #{index_cfg[:key]}: day_type=#{context.day_type} session=#{context.session} " \
            "regime=#{context.regime} score=#{context.score} stability=#{context.stability} (not tradable)"
          )
          return true
        end
        Rails.logger.debug do
          "[Signal] TradingContext PASSED #{index_cfg[:key]}: #{context.day_type}/#{context.session}/#{context.regime} " \
            "score=#{context.score} stability=#{context.stability}"
        end
        false
      end

      def evaluate_entry_quality(index_cfg, primary_series, primary_analysis, final_direction, regime)
        quality_result = Signal::EntryQualityFilter.evaluate(
          series: primary_series,
          supertrend_result: primary_analysis[:supertrend],
          adx_value: primary_analysis[:adx_value],
          direction: final_direction,
          regime: regime,
          index_key: index_cfg[:key]
        )
        unless quality_result[:pass]
          Rails.logger.info(
            "[Signal] EntryQualityFilter REJECTED #{index_cfg[:key]} #{final_direction}: " \
            "#{quality_result[:reject_reason]} (score=#{quality_result[:score]})"
          )
        end
        quality_result
      end

      def execute_execution_gates(index_cfg, instrument, primary_series, final_direction, signals_cfg)
        if signals_cfg.fetch(:enable_institutional_filter, false)
          filter = Entries::EntryFilterEngine.new(series: primary_series, symbol: index_cfg[:key])
          unless filter.valid_entry?(direction: final_direction)
            msg = "Missing Structure/Liquidity/Volatility alignment"
            Rails.logger.warn("[Signal] EntryFilterEngine BLOCKED #{index_cfg[:key]}: #{msg}")
            ActionCable.server.broadcast("dashboard", {
              type: "toast",
              level: "warning",
              title: "Institutional Filter Blocked",
              message: "#{index_cfg[:key]} #{final_direction}: #{msg}"
            })
            Signal::StateTracker.reset(index_cfg[:key])
            return nil
          end
          Rails.logger.info("[Signal] EntryFilterEngine PASSED for #{index_cfg[:key]}")
        else
          Rails.logger.debug { "[Signal] EntryFilterEngine SKIPPED for #{index_cfg[:key]} (disabled in config)" }
        end

        permission = Trading::PermissionResolver.resolve(symbol: index_cfg[:key], instrument: instrument)
        if permission == :blocked
          Rails.logger.info("[Signal] PermissionResolver BLOCKED #{index_cfg[:key]} - no trade")
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        enable_smc_permission = signals_cfg.fetch(:enable_smc_avrz_permission, true)
        enable_smc_alignment  = signals_cfg.fetch(:enable_smc_decision_alignment, true)

        if enable_smc_permission && enable_smc_alignment
          smc_decision = get_smc_decision(index_cfg, instrument, signals_cfg, final_direction)
          unless smc_decision_aligned?(smc_decision, final_direction)
            Rails.logger.info(
              "[Signal] SMC Decision BLOCKED #{index_cfg[:key]}: " \
              "signal=#{final_direction}, smc=#{smc_decision} (misaligned or no_trade)"
            )
            Signal::StateTracker.reset(index_cfg[:key])
            return nil
          end
          Rails.logger.info("[Signal] SMC Decision CONFIRMED #{index_cfg[:key]}: #{smc_decision} aligns with #{final_direction}")
        else
          smc_decision = final_direction == :bullish ? :call : :put
        end

        ltf_confluence_snap = fetch_ltf_confluence_snapshot_if_needed(
          instrument: instrument,
          signals_cfg: signals_cfg
        )
        return nil if blocked_by_smc_confluence_gate?(
          index_cfg: index_cfg,
          final_direction: final_direction,
          signals_cfg: signals_cfg,
          snap: ltf_confluence_snap
        )

        momentum_result = Signal::MomentumValidator.validate(
          instrument: instrument,
          series: primary_series,
          direction: final_direction
        )
        Rails.logger.info("[Signal] Momentum Score for #{index_cfg[:key]}: #{momentum_result.score}/3")

        gate_result_hash(
          permission: permission,
          smc_decision: smc_decision,
          momentum_score: momentum_result.score,
          signals_cfg: signals_cfg,
          ltf_confluence_snap: ltf_confluence_snap
        )
      end

      def execute_no_trade_gate(index_cfg:, instrument:, signals_cfg:)
        return { expiry_date: nil, chain_data: nil } unless signals_cfg.fetch(:enable_no_trade_engine, true)

        bars_1m = recent_no_trade_bars(instrument: instrument, interval: '1')
        bars_5m = recent_no_trade_bars(instrument: instrument, interval: '5')

        if bars_1m.size < 10 || bars_5m.size < 15
          Rails.logger.warn(
            "[Signal] NoTradeEngine BLOCKED #{index_cfg[:key]}: insufficient context " \
            "(1m=#{bars_1m.size}, 5m=#{bars_5m.size})"
          )
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        expiry_date = Options::DerivativeChainAnalyzer.new(index_key: index_cfg[:key]).nearest_expiry
        chain_data = instrument.fetch_option_chain(expiry_date)

        context = Entries::NoTradeContextBuilder.build(
          index: index_cfg[:key],
          bars_1m: bars_1m,
          bars_5m: bars_5m,
          option_chain: chain_data,
          time: Time.current
        )
        result = Entries::NoTradeEngine.validate(context)

        unless result.allowed
          Rails.logger.info(
            "[Signal] NoTradeEngine BLOCKED #{index_cfg[:key]}: " \
            "score=#{result.score} reasons=#{result.reasons.join('; ')}"
          )
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        Rails.logger.info("[Signal] NoTradeEngine PASSED #{index_cfg[:key]}: score=#{result.score}")
        { expiry_date: expiry_date, chain_data: chain_data }
      rescue StandardError => e
        Rails.logger.error("[Signal] NoTradeEngine ERROR #{index_cfg[:key]}: #{e.class} #{e.message}")
        Signal::StateTracker.reset(index_cfg[:key])
        nil
      end

      def recent_no_trade_bars(instrument:, interval:)
        instrument.candle_series(interval: interval)&.candles&.last(20) || []
      end

      def fetch_ltf_confluence_snapshot_if_needed(instrument:, signals_cfg:)
        digest = signals_cfg.fetch(:enable_smc_confluence_digest, false)
        gating = signals_cfg.fetch(:enable_smc_confluence_gating, false)
        return nil unless digest || gating

        Smc::Confluence::LtfSnapshot.fetch(instrument: instrument, signals_cfg: signals_cfg)
      end

      def blocked_by_smc_confluence_gate?(index_cfg:, final_direction:, signals_cfg:, snap:)
        return false unless signals_cfg.fetch(:enable_smc_confluence_gating, false)
        return false if Smc::Confluence::LtfSnapshot.gate_passes?(final_direction, snap)

        Rails.logger.info(
          "[Signal] SMC Confluence gate BLOCKED #{index_cfg[:key]}: " \
          "direction=#{final_direction} (LTF Pine confluence signal not confirmed)"
        )
        Signal::StateTracker.reset(index_cfg[:key])
        true
      end

      def gate_result_hash(permission:, smc_decision:, momentum_score:, signals_cfg:, ltf_confluence_snap:)
        out = { permission: permission, smc_decision: smc_decision, momentum_score: momentum_score }
        if signals_cfg.fetch(:enable_smc_confluence_digest, false) && ltf_confluence_snap
          out[:smc_confluence_ltf_summary] = ltf_confluence_snap[:summary]
        end
        out
      end

      def execute_options_analysis(index_cfg, instrument, final_direction, primary_series, effective_validation_mode,
                                   expiry_date: nil, chain_data: nil)
        expiry_blocked = expiry_trade_allowed?(index_cfg[:key]) == false
        expiry_date  ||= Options::DerivativeChainAnalyzer.new(index_key: index_cfg[:key]).nearest_expiry
        chain_data   ||= instrument.fetch_option_chain(expiry_date)

        gamma_pressure_result = if chain_data
                                  detector = Options::GammaRampDetector.new(
                                    index_key: index_cfg[:key],
                                    expiry_date: expiry_date,
                                    chain_data: chain_data
                                  )
                                  {
                                    score: detector.gamma_pressure_score(direction: final_direction),
                                    strike: detector.ramp_strike(direction: final_direction)&.dig(:strike)
                                  }
                                else
                                  { score: 0.0, strike: nil }
                                end

        iv_rank_result    = validate_iv_rank(index_cfg, primary_series, effective_validation_mode)
        theta_risk_result = validate_theta_risk(index_cfg, final_direction, effective_validation_mode)

        {
          gamma_pressure: gamma_pressure_result,
          iv_rank: iv_rank_result,
          theta_risk: theta_risk_result,
          expiry_blocked: expiry_blocked,
          expiry_date: expiry_date,
          chain_data: chain_data
        }
      end

      def build_diagnostic_metadata(index_cfg:, final_direction:, primary_analysis:, confirmation_analysis:,
                                    regime:, regime_result:, ta_result:, options_analysis:,
                                    validation_result:, state_snapshot:, effective_validation_mode:,
                                    signals_cfg:, primary_tf:, effective_timeframe:, confirmation_tf:,
                                    enable_confirmation:, smc_decision:, permission:,
                                    smc_confluence_ltf_summary: nil,
                                    strategy_recommendation: nil, use_strategy_recommendations: false)
        Signal::MetadataBuilder.build(
          index_cfg: index_cfg,
          final_direction: final_direction,
          primary_analysis: primary_analysis,
          confirmation_analysis: confirmation_analysis,
          regime: regime,
          regime_result: regime_result,
          ta_result: ta_result,
          options_analysis: options_analysis,
          validation_result: validation_result,
          state_snapshot: state_snapshot,
          effective_validation_mode: effective_validation_mode,
          signals_cfg: signals_cfg,
          primary_tf: primary_tf,
          effective_timeframe: effective_timeframe,
          confirmation_tf: confirmation_tf,
          enable_confirmation: enable_confirmation,
          smc_decision: smc_decision,
          permission: permission,
          smc_confluence_ltf_summary: smc_confluence_ltf_summary,
          strategy_name: strategy_recommendation&.dig(:strategy_name) || 'supertrend_adx',
          strategy_mode: use_strategy_recommendations ? 'recommended' : 'supertrend_adx'
        )
      end

      def options_analysis_gate_blocks_entry?(signal:, index_cfg:, options_analysis:)
        gate = AlgoConfig.fetch.dig(:signals, :options_analysis_gate) || {}
        return false unless gate[:enabled]

        if gate.fetch(:block_on_iv_rank_failure, true)
          iv = options_analysis[:iv_rank]
          if iv.is_a?(Hash) && iv[:valid] == false
            Rails.logger.info(
              "[Signal] OptionsAnalysisGate BLOCKED #{index_cfg[:key]}: #{iv[:name]} — #{iv[:message]}"
            )
            detail = [iv[:name], iv[:message]].compact.join(' — ')
            record_signal_skip(
              signal,
              "options_analysis_iv_rank: #{detail.presence || 'validation failed'}",
              stage: 'options_analysis',
              code: 'iv_rank_failure'
            )
            Signal::StateTracker.reset(index_cfg[:key])
            return true
          end
        end

        if gate.fetch(:block_on_theta_risk_failure, true)
          theta = options_analysis[:theta_risk]
          if theta.is_a?(Hash) && theta[:valid] == false
            Rails.logger.info(
              "[Signal] OptionsAnalysisGate BLOCKED #{index_cfg[:key]}: #{theta[:name]} — #{theta[:message]}"
            )
            detail = [theta[:name], theta[:message]].compact.join(' — ')
            record_signal_skip(
              signal,
              "options_analysis_theta_risk: #{detail.presence || 'validation failed'}",
              stage: 'options_analysis',
              code: 'theta_risk_failure'
            )
            Signal::StateTracker.reset(index_cfg[:key])
            return true
          end
        end

        false
      end

      def execute_entry_gate(index_cfg:, instrument:, signal:, final_direction:, primary_series:,
                             options_analysis:, momentum_score:, permission:, smc_decision:)
        expiry_blocked = options_analysis[:expiry_blocked]
        expiry_date    = options_analysis[:expiry_date]
        chain_data     = options_analysis[:chain_data]

        if expiry_blocked
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          record_signal_skip(
            signal,
            'expiry_midday_decay: Midday decay period blocked entry for this expiry',
            stage: 'expiry_model',
            code: 'expiry_midday_decay'
          )
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        if options_analysis_gate_blocks_entry?(signal: signal, index_cfg: index_cfg,
                                               options_analysis: options_analysis)
          return nil
        end

        expected_spot_move = begin
          atr = primary_series.atr(14)
          atr&.to_f
        rescue StandardError
          nil
        end

        unless expected_spot_move&.positive?
          Rails.logger.info("[Signal] Missing expected_spot_move (ATR) -> BLOCK #{index_cfg[:key]}")
          record_signal_skip(
            signal,
            'missing_atr: Expected spot move (14-period ATR) missing or non-positive',
            stage: 'strike_selection',
            code: 'missing_atr'
          )
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        strike_result = Options::ChainAnalyzer.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: final_direction,
          permission: permission,
          expected_spot_move: expected_spot_move,
          momentum_score: momentum_score
        )

        if strike_result.picks.blank?
          skip_reason = strike_result.failure_reason.presence || 'No suitable option strikes'
          Rails.logger.warn("[Signal] No suitable option strikes for #{index_cfg[:key]} #{final_direction}: #{skip_reason}")
          record_signal_skip(
            signal,
            skip_reason,
            stage: 'strike_selection',
            code: strike_result.failure_code
          )
          ActionCable.server.broadcast("dashboard", {
            type: "toast",
            level: "warning",
            title: "Options Strike Blocked",
            message: "#{index_cfg[:key]} #{final_direction}: #{skip_reason}"
          })
          return nil
        end

        picks = strike_result.picks
        Rails.logger.info("[Signal] Found #{picks.size} option picks for #{index_cfg[:key]}: #{picks.pluck(:symbol).join(', ')}")

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        if signals_cfg.fetch(:enable_option_premium_momentum_gate, true)
          premium_validation = Signal::MomentumValidator.validate_option_pick(
            index_key: index_cfg[:key],
            pick: picks.first,
            direction: final_direction
          )
          unless premium_validation[:confirms]
            Rails.logger.info(
              "[Signal] Option premium momentum BLOCKED #{index_cfg[:key]}: #{premium_validation[:reason]}"
            )
            record_signal_skip(
              signal,
              "option_premium_momentum: #{premium_validation[:reason]}",
              stage: 'premium_momentum',
              code: 'option_premium_momentum'
            )
            Signal::StateTracker.reset(index_cfg[:key])
            return nil
          end
        end

        market_context_extra, mc_gate_blocked, mc_block_detail = evaluate_market_context_for_entry(
          index_cfg: index_cfg,
          primary_series: primary_series,
          expiry_date: expiry_date,
          chain_data: chain_data,
          final_direction: final_direction,
          pick: picks.first,
          smc_decision: smc_decision
        )

        if mc_gate_blocked
          record_signal_skip(
            signal,
            "market_context_gate: #{mc_block_detail.presence || 'blocked'}",
            stage: 'market_context',
            code: 'market_permission_gate'
          )
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        { picks: picks, market_context_extra: market_context_extra, execution_permission: permission }
      end

      def trigger_entry_flow(index_cfg:, instrument:, signal:, picks:, final_direction:,
                             primary_series:, primary_tf:, entry_primary:,
                             diagnostic_metadata:, quality_result:, market_context_extra:, execution_permission:)
        supertrend_direct_entry = (entry_primary == 'supertrend')

        entry_metadata = diagnostic_metadata.merge(market_context_extra).merge(
          entry_contract: supertrend_direct_entry ? 'supertrend_machine_v1' : 'bos_machine_v1',
          permission: execution_permission,
          entry_quality_score: quality_result[:score],
          entry_quality_breakdown: quality_result[:breakdown]
        )

        if supertrend_direct_entry
          entry_metadata.merge!(
            bos_id: "st_#{index_cfg[:key]}_#{Time.current.to_i}",
            bos_timeframe: primary_tf,
            bos_origin_price: primary_series.candles.last&.close,
            bos_level: primary_series.candles.last&.close,
            entry_underlying_price: primary_series.candles.last&.close
          )
          picks.each do |pick|
            entered = Entries::EntryGuard.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: final_direction,
              scale_multiplier: 1,
              entry_metadata: entry_metadata,
              permission: execution_permission,
              signal: signal
            )
            break if entered
          end
        else
          Entries::BosEntryEngine.run_for(
            index_cfg: index_cfg,
            instrument: instrument,
            direction: final_direction,
            picks: picks,
            entry_metadata: entry_metadata,
            permission: execution_permission,
            signal: signal
          )
        end
      end

      # --- Dynamic Configuration Helpers ---

      def dynamic_config_enabled?
        AlgoConfig.fetch.dig(:signals, :use_optimized_params) != false
      end

      def resolved_supertrend_cfg(instrument, interval, signals_cfg)
        base_cfg = (signals_cfg[:supertrend] || { period: 7, multiplier: 3.0 }).dup

        return base_cfg unless dynamic_config_enabled?

        # Try to find optimized params for this specific instrument + interval
        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :supertrend).first
        return base_cfg unless optimized && optimized.params.is_a?(Hash)

        # Map optimized keys (atr_period, multiplier) to service keys (period, base_multiplier)
        params = optimized.params.symbolize_keys
        base_cfg[:period] = params[:atr_period] if params[:atr_period]
        base_cfg[:base_multiplier] = params[:multiplier] if params[:multiplier]

        Rails.logger.info("[Signal] 🚀 Using optimized Supertrend for #{instrument.symbol_name} @ #{interval}: #{base_cfg}")
        base_cfg
      end

      def resolved_adx_min(instrument, interval, index_cfg, timeframe_label)
        static_min = index_cfg.dig(:adx_thresholds, timeframe_label == 'primary' ? :primary_min_strength : :confirmation_min_strength) || 15

        return static_min unless dynamic_config_enabled?

        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :adx).first
        return static_min unless optimized && optimized.params.is_a?(Hash)

        optimized_min = optimized.params.symbolize_keys[:min_strength]
        return static_min unless optimized_min

        Rails.logger.info("[Signal] 🚀 Using optimized ADX min for #{instrument.symbol_name} @ #{interval}: #{optimized_min}")
        optimized_min
      end

      # --- Dynamic Configuration Helpers ---

      def dynamic_config_enabled?
        AlgoConfig.fetch.dig(:signals, :use_optimized_params) != false
      end

      def resolved_supertrend_cfg(instrument, interval, signals_cfg)
        base_cfg = (signals_cfg[:supertrend] || { period: 7, multiplier: 3.0 }).dup

        return base_cfg unless dynamic_config_enabled?

        # Try to find optimized params for this specific instrument + interval
        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :supertrend).first
        return base_cfg unless optimized && optimized.params.is_a?(Hash)

        # Map optimized keys (atr_period, multiplier) to service keys (period, base_multiplier)
        params = optimized.params.symbolize_keys
        base_cfg[:period] = params[:atr_period] if params[:atr_period]
        base_cfg[:base_multiplier] = params[:multiplier] if params[:multiplier]

        Rails.logger.info("[Signal] 🚀 Using optimized Supertrend for #{instrument.symbol_name} @ #{interval}: #{base_cfg}")
        base_cfg
      end

      def resolved_adx_min(instrument, interval, index_cfg, timeframe_label)
        static_min = index_cfg.dig(:adx_thresholds, timeframe_label == 'primary' ? :primary_min_strength : :confirmation_min_strength) || 15

        return static_min unless dynamic_config_enabled?

        optimized = BestIndicatorParam.best_for_indicator(instrument.id, interval, :adx).first
        return static_min unless optimized && optimized.params.is_a?(Hash)

        optimized_min = optimized.params.symbolize_keys[:min_strength]
        return static_min unless optimized_min

        Rails.logger.info("[Signal] 🚀 Using optimized ADX min for #{instrument.symbol_name} @ #{interval}: #{optimized_min}")
        optimized_min
      end

      private

      def record_signal_skip(signal, reason)
        signal&.record_entry_outcome('skipped', reason)
      end
    end
  end
end
# rubocop:enable Metrics/BlockNesting
