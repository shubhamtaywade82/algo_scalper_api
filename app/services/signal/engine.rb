# frozen_string_literal: true

# rubocop:disable Metrics/BlockNesting

# rubocop:disable Metrics/BlockNesting

module Signal
  # Stock Supertrend options-buying pipeline: 1m flip → chop gate → ATM strike → EntryGuard.
  class Engine
    class << self
      def run_for(index_cfg, regime_state: nil)
        return unless tradable_session?(index_cfg)

        instrument = fetch_instrument(index_cfg)
        return unless instrument

        signals_cfg = AlgoConfig.fetch[:signals] || {}
        run_mode = AlgoConfig.run_mode
        exit_testing_mode = run_mode == 'exit_testing'
        entry_primary = if exit_testing_mode
                          'supertrend_adx'
                        else
                          (signals_cfg.dig(:entry_strategy, :primary) || signals_cfg[:entry_strategy].to_s).to_s.strip.downcase
                        end

        primary_tf = exit_testing_mode ? '1m' : (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_confirmation = exit_testing_mode ? false : signals_cfg.fetch(:enable_confirmation_timeframe, true)
        confirmation_tf = if enable_confirmation && signals_cfg[:confirmation_timeframe].present?
                            signals_cfg[:confirmation_timeframe].to_s
                          end

        # Initialize diagnostic variables to prevent NoMethodError in cross-strategy metadata building
        ta_result = nil
        regime_result = { regime: 'UNKNOWN', confidence: 0, metrics: {} }
        regime = 'UNKNOWN'

        if entry_primary == 'supertrend'
          result = execute_supertrend_only_flow(index_cfg, instrument, signals_cfg, primary_tf)
        else
          # ===== INDEX TECHNICAL ANALYSIS STEP (DIAGNOSTICS & OPTIONAL FILTER) =====
          # Always performed for diagnostics. Filter is optional via signals.enable_index_ta_filter.
          enable_index_ta_filter = signals_cfg.fetch(:enable_index_ta_filter, false)
          ta_min_confidence = signals_cfg[:ta_min_confidence] || 0.6
          ta_timeframes = signals_cfg[:ta_timeframes] || [5, 15, 60]
          ta_days_back = signals_cfg[:ta_days_back] || 30

          index_symbol = index_cfg[:key].to_s.downcase.to_sym
          ta_analyzer = IndexTechnicalAnalyzer.new(index_symbol)
          ta_analysis = ta_analyzer.call(timeframes: ta_timeframes, days_back: ta_days_back)

          if ta_analysis[:success] && ta_analyzer.success?
            ta_result = ta_analyzer.result
            Rails.logger.info(
              "[Signal] Index TA for #{index_cfg[:key]}: signal=#{ta_result[:signal]}, " \
              "confidence=#{ta_result[:confidence].round(2)}, bias=#{ta_result.dig(:bias_summary, :summary, :bias)}"
            )

            # Only block if filter is explicitly enabled (default is now false for diagnostics)
            if enable_index_ta_filter && (ta_result[:signal] == :neutral || ta_result[:confidence] < ta_min_confidence)
              Rails.logger.info(
                "[Signal] Skipping signal generation for #{index_cfg[:key]} (TA Filter ACTIVE): " \
                "TA signal=#{ta_result[:signal]}, confidence=#{ta_result[:confidence].round(2)}"
              )
              return
            end
          else
            Rails.logger.warn("[Signal] Index TA failed for #{index_cfg[:key]}: #{ta_analyzer.error}")
          end

          primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
          enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, true)
          confirmation_tf = (signals_cfg[:confirmation_timeframe].presence&.to_s if enable_confirmation)

          # Check if strategy-based recommendations are enabled
          use_strategy_recommendations = exit_testing_mode ? false : signals_cfg.fetch(:use_strategy_recommendations, false)

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

            if multi_indicator_enabled?(index_cfg, signals_cfg)
              primary_analysis = analyze_with_multi_indicators(
                index_cfg: index_cfg,
                instrument: instrument,
                timeframe: primary_tf,
                signals_cfg: signals_cfg
              )
            else
              primary_analysis = analyze_timeframe(
                index_cfg: index_cfg,
                instrument: instrument,
                timeframe: primary_tf,
                supertrend_cfg: supertrend_cfg,
                adx_min_strength: adx_min_strength
              )
            end
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

          primary_series = primary_analysis[:series]
          if exit_testing_mode
            regime_result = { regime: 'EXIT_TESTING', confidence: 0, metrics: {} }
            regime = regime_result[:regime]
            effective_validation_mode = 'exit_testing'
            validation_result = { valid: true, reason: 'Exit-testing mode: 1m Supertrend+ADX only' }
            Rails.logger.info("[Signal] Exit-testing mode active for #{index_cfg[:key]}: forcing 1m Supertrend+ADX only.")
          else
            # ===== MARKET REGIME & DIRECTION GATE =====
            # Always compute regime for diagnostics. Filter via signals.enable_direction_gate.
            regime_result = MarketRegimeDetector.new(primary_series).detect
            regime = regime_result[:regime]

            # DYNAMIC VALIDATION MODE: Use conservative mode in ranging/choppy markets
            # NOTE: Use local variable — do NOT mutate signals_cfg (it's a cached AlgoConfig reference)
            effective_validation_mode = if %w[RANGING CHOPPY].include?(regime)
                                          Rails.logger.info("[Signal] Switching to CONSERVATIVE validation for #{index_cfg[:key]} due to #{regime} regime")
                                          'conservative'
                                        else
                                          signals_cfg[:validation_mode]
                                        end

            enable_direction_gate = signals_cfg.fetch(:enable_direction_gate, false)

            if enable_direction_gate
              trade_side = final_direction == :bullish ? :CE : :PE

              # Hard block for non-trending markets as per options buying requirements
              if %w[RANGING CHOPPY INSUFFICIENT_DATA].include?(regime)
                Rails.logger.info(
                  "[Signal] DirectionGate BLOCKED #{index_cfg[:key]}: Market is #{regime}. Skipping to avoid theta decay."
                )
                Signal::StateTracker.reset(index_cfg[:key])
                return
              end

              # Verify alignment with expected trade direction
              aligned = (regime == 'TRENDING_UP' && trade_side == :CE) ||
                        (regime == 'TRENDING_DOWN' && trade_side == :PE)

              unless aligned
                Rails.logger.info(
                  "[Signal] DirectionGate BLOCKED #{index_cfg[:key]}: Counter-trend trade. #{trade_side} requested vs #{regime}."
                )
                Signal::StateTracker.reset(index_cfg[:key])
                return
              end
              Rails.logger.debug { "[Signal] DirectionGate ALLOWED #{index_cfg[:key]}: #{trade_side} in #{regime}" }
            end

            validation_result = comprehensive_validation(index_cfg, final_direction, primary_series,
                                                         primary_analysis[:supertrend], { value: primary_analysis[:adx_value] },
                                                         validation_mode: effective_validation_mode)
          end

          result = {
            direction: final_direction,
            primary_analysis: primary_analysis,
            confirmation_analysis: confirmation_analysis,
            primary_series: primary_series,
            ta_result: ta_result,
            regime_result: regime_result,
            regime: regime,
            validation_result: validation_result,
            effective_validation_mode: effective_validation_mode,
            effective_timeframe: effective_timeframe,
            strategy_recommendation: strategy_recommendation,
            use_strategy_recommendations: use_strategy_recommendations
          }
        end

        return unless result

        final_direction = result[:direction]
        primary_analysis = result[:primary_analysis]
        confirmation_analysis = result[:confirmation_analysis]
        primary_series = result[:primary_series]
        ta_result = result[:ta_result]
        regime_result = result[:regime_result]
        regime = result[:regime]
        validation_result = result[:validation_result]
        effective_validation_mode = result[:effective_validation_mode]
        effective_timeframe = result[:effective_timeframe] || primary_tf
        strategy_recommendation = result[:strategy_recommendation]
        use_strategy_recommendations = result[:use_strategy_recommendations] || false

        if signals_cfg[:halt_on_validation_failure] && validation_result && validation_result[:valid] == false
          Rails.logger.info("[Signal] halt_on_validation_failure BLOCKED #{index_cfg[:key]}: #{validation_result[:reason]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        # 5. Trading Context Gate
        if trading_context_blocked?(index_cfg, primary_series, primary_analysis, regime_result, regime_state, exit_testing_mode, signals_cfg)
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        permission = :exit_testing
        smc_decision = final_direction == :bullish ? :call : :put

        if exit_testing_mode?
          Rails.logger.info("[Signal] Exit-testing mode: skipping entry filter, permission/SMC gating, and momentum validation.")
        else
          # ===== INSTITUTIONAL ENTRY FILTER (Structure + Liquidity + Volatility) =====
          filter = Entries::EntryFilterEngine.new(series: primary_series, symbol: index_cfg[:key])
          unless filter.valid_entry?(direction: final_direction)
            Rails.logger.warn("[Signal] EntryFilterEngine BLOCKED #{index_cfg[:key]}: Missing Structure/Liquidity/Volatility alignment")
            Signal::StateTracker.reset(index_cfg[:key])
            return
          end
          Rails.logger.info("[Signal] EntryFilterEngine PASSED for #{index_cfg[:key]}")
          # ===== END INSTITUTIONAL ENTRY FILTER =====

          Rails.logger.info("[Signal] Proceeding with #{final_direction} signal for #{index_cfg[:key]}")

          # ===== PERMISSION RESOLUTION (HARD) =====
          permission = Trading::PermissionResolver.resolve(symbol: index_cfg[:key], instrument: instrument)
          if permission == :blocked
            Rails.logger.info("[Signal] PermissionResolver BLOCKED #{index_cfg[:key]} - no trade")
            Signal::StateTracker.reset(index_cfg[:key])
            return
          end
          # ===== END PERMISSION RESOLUTION =====

          # ===== SMC DECISION ALIGNMENT (HARD FILTER) =====
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
            smc_decision = final_direction == :bullish ? :call : :put
            Rails.logger.debug { "[Signal] SMC Decision alignment check SKIPPED for #{index_cfg[:key]} (SMC+AVRZ disabled)" }
          end
          # ===== END SMC DECISION ALIGNMENT =====

          # ===== MOMENTUM VALIDATION =====
          momentum_result = Signal::MomentumValidator.validate(
            instrument: instrument,
            series: primary_series,
            direction: final_direction
          )
          momentum_score = momentum_result.score
          Rails.logger.info("[Signal] Momentum Score for #{index_cfg[:key]}: #{momentum_score}/3")
          # ===== END MOMENTUM VALIDATION =====
        end

        # 8. Persistence Pre-checks
        state_snapshot = Signal::StateTracker.record(
          index_key: index_cfg[:key],
          direction: final_direction,
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          config: signals_cfg
        )

        # 9. Options Analysis
        execute_options_analysis(index_cfg, instrument, final_direction, primary_series, effective_validation_mode)

        # 10. Metadata Building
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
          validation_mode: effective_validation_mode || signals_cfg[:validation_mode] || 'balanced',
          validation_passed: validation_result[:valid],
          state_count: state_snapshot[:count],
          state_multiplier: state_snapshot[:multiplier],
          original_timeframe: primary_tf,
          # SMC/Permission integration
          smc_decision: smc_decision.to_s,
          smc_permission: permission.to_s
        }

        TradingSignal.create_from_analysis(
          index_key: index_cfg[:key],
          direction: final_direction.to_s,
          timeframe: effective_timeframe,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: calculate_confidence_score(
            primary_analysis: primary_analysis,
            confirmation_analysis: confirmation_analysis,
            validation_result: validation_result
          ),
          metadata: diagnostic_metadata
        )

        # Rails.logger.info("[Signal] Signal state for #{index_cfg[:key]}: count=#{state_snapshot[:count]} multiplier=#{state_snapshot[:multiplier]}")

        # ===== EXPIRY DAY SESSION FILTER =====
        # Avoid midday decay periods on expiry days for index options
        if expiry_trade_allowed?(index_cfg[:key]) == false
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
        # ===== END EXPIRY DAY SESSION FILTER =====

        # ===== GAMMA RAMP DETECTION =====
        # Detect if price is approaching an OI cluster for explosive potential
        expiry_date = resolve_nearest_expiry_date(index_cfg: index_cfg, no_trade_gate: nil)
        chain_data = expiry_date.present? ? instrument.fetch_option_chain(expiry_date) : nil

        if chain_data
          gamma_detector = Options::GammaRampDetector.new(
            index_key: index_cfg[:key],
            expiry_date: expiry_date,
            chain_data: chain_data
          )
          gamma_ramp_strike = gamma_detector.ramp_strike(direction: final_direction)
          if gamma_ramp_strike
            Rails.logger.info("[Signal] GAMMA RAMP DETECTED for #{index_cfg[:key]} at strike #{gamma_ramp_strike[:strike]}")
            diagnostic_metadata[:gamma_ramp_strike] = gamma_ramp_strike[:strike]
            diagnostic_metadata[:gamma_pressure] = gamma_detector.gamma_pressure_score(direction: final_direction)
          end
        end
        # ===== END GAMMA RAMP DETECTION =====

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
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        execution_permission = effective_execution_permission(permission)

        picks = Options::ChainAnalyzer.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: final_direction,
          permission: execution_permission,
          expected_spot_move: expected_spot_move,
          momentum_score: momentum_score
        )
        # ===== END STRIKE QUALIFICATION LAYER =====

        if picks.blank?
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{final_direction}")
          return
        end

        Rails.logger.info("[Signal] Found #{picks.size} option picks for #{index_cfg[:key]}: #{picks.pluck(:symbol).join(', ')}")

        # Prepare entry metadata to pass to EntryGuard
        supertrend_direct_entry = (entry_primary == 'supertrend') || exit_testing_mode?
        entry_metadata = diagnostic_metadata.merge(
          entry_contract: supertrend_direct_entry ? 'supertrend_machine_v1' : 'bos_machine_v1',
          permission: execution_permission
        )

        if supertrend_direct_entry
          # Supertrend-only mode: enter directly on signal without BOS pullback wait.
          # Add stub BOS fields required by EntryGuard's contract check.
          Rails.logger.info("[Signal] Exit-testing mode: using direct EntryGuard path (no BOS state machine).") if exit_testing_mode?
          entry_metadata.merge!(
            bos_id: "st_#{index_cfg[:key]}_#{Time.current.to_i}",
            bos_timeframe: primary_tf,
            bos_origin_price: primary_series.candles.last&.close,
            bos_level: primary_series.candles.last&.close
          )
          picks.each do |pick|
            entered = Entries::EntryGuard.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: final_direction,
              scale_multiplier: 1,
              entry_metadata: entry_metadata,
              permission: execution_permission
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
            permission: execution_permission
          )
        end

        # Rails.logger.info("[Signal] Completed analysis for #{index_cfg[:key]}")
      rescue StandardError => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
        Rails.logger.error("[Signal] #{index_cfg[:key]} #{e.class} #{e.message}")
        Rails.logger.error("[Signal] Backtrace: #{e.backtrace.first(5).join(', ')}")
      end

      def tradable_session?(index_cfg)
        if defined?(TradingSession::Service) && TradingSession::Service.respond_to?(:market_closed?) && TradingSession::Service.market_closed?
          Rails.logger.debug { "[Signal] Market closed - skipping analysis for #{index_cfg[:key]}" }
          return false
        end

        Rails.logger.info("\n\n[Signal] ----------------------------------------------------- Starting analysis for #{index_cfg[:key]} (IDX_I) --------------------------------------------------------")
        true
      end

      def fetch_instrument(index_cfg)
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.error("[Signal] Could not find instrument for #{index_cfg[:key]}")
        end
        instrument
      end

      def initialize_analysis_context(signals_cfg, exit_testing_mode)
        entry_primary = if exit_testing_mode
                          'supertrend_adx'
                        else
                          (signals_cfg.dig(:entry_strategy, :primary) || signals_cfg[:entry_strategy].to_s).to_s.strip.downcase
                        end

        primary_tf = exit_testing_mode ? '1m' : (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_confirmation = exit_testing_mode ? false : signals_cfg.fetch(:enable_confirmation_timeframe, true)
        confirmation_tf = (signals_cfg[:confirmation_timeframe].to_s if enable_confirmation && signals_cfg[:confirmation_tf].present?)

        {
          entry_primary: entry_primary,
          primary_tf: primary_tf,
          enable_confirmation: enable_confirmation,
          confirmation_tf: confirmation_tf
        }
      end

      def execute_supertrend_only_flow(index_cfg, instrument, signals_cfg, primary_tf)
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
        primary_series = primary_analysis[:series]
        validation_result = comprehensive_validation(
          index_cfg, final_direction, primary_series,
          primary_analysis[:supertrend], { value: primary_analysis[:adx_value] },
          supertrend_only: true
        )

        # Collect diagnostics
        ta_result = perform_diagnostic_ta(index_cfg, signals_cfg)
        regime_result = MarketRegimeDetector.new(primary_series).detect

        {
          direction: final_direction,
          primary_analysis: primary_analysis,
          confirmation_analysis: nil,
          primary_series: primary_series,
          ta_result: ta_result,
          regime_result: regime_result,
          regime: regime_result[:regime],
          validation_result: validation_result,
          effective_validation_mode: nil
        }
      end

      def perform_diagnostic_ta(index_cfg, signals_cfg)
        ta_timeframes = signals_cfg[:ta_timeframes] || [5, 15, 60]
        ta_days_back = signals_cfg[:ta_days_back] || 30
        index_symbol = index_cfg[:key].to_s.downcase.to_sym
        ta_analyzer = IndexTechnicalAnalyzer.new(index_symbol)
        ta_analysis = ta_analyzer.call(timeframes: ta_timeframes, days_back: ta_days_back)
        ta_analysis[:success] ? ta_analyzer.result : nil
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
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
        Rails.logger.error("[Signal] Timeframe analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      def analyze_multi_timeframe(index_cfg:, instrument:)
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        primary_tf = (signals_cfg[:primary_timeframe] || signals_cfg[:timeframe] || '5m').to_s
        enable_confirmation = signals_cfg.fetch(:enable_confirmation_timeframe, true)
        confirmation_tf = (signals_cfg[:confirmation_timeframe].presence&.to_s if enable_confirmation)

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
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
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
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
        Rails.logger.error("[Signal] Strategy-based analysis failed for #{index_cfg[:key]} @ #{timeframe}: #{e.class} - #{e.message}")
        { status: :error, message: e.message }
      end

      # Build clear entry path identifier for tracking
      # Format: "strategy_timeframe_confirmation" e.g., "recommended_5m_none" or "supertrend_adx_1m_5m"
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

      # Get validation mode configuration
      # @param override_mode [String, nil] Override the configured validation mode (e.g. 'conservative' for RANGING/CHOPPY regimes)

      def comprehensive_validation(index_cfg, direction, series, supertrend_result, adx, supertrend_only: false, validation_mode: nil)
        mode_config = get_validation_mode_config(override_mode: validation_mode)
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
        # Loss Avoidance: Enforce ADX even in supertrend_only mode if filter is enabled,
        # as analysis shows ADX < 15 has 16.7% win rate across all strategies.
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        enable_adx_filter = signals_cfg.fetch(:enable_adx_filter, true)
        if enable_adx_filter
          adx_result = validate_adx_strength(index_cfg, adx, supertrend_result, mode_config)
          validation_checks << adx_result
        elsif !supertrend_only
          # Rails.logger.debug('[Signal] ADX validation skipped (filter disabled)')
          validation_checks << { valid: true, name: 'ADX Strength', message: 'ADX filter disabled' }
        end

        # 4. Trend Confirmation - Multiple signal validation (if enabled); skipped when supertrend_only
        if !supertrend_only && mode_config[:require_trend_confirmation]
          trend_result = validate_trend_confirmation(supertrend_result, series)
          validation_checks << trend_result
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

        # Determine overall validation result
        failed_checks = validation_checks.reject { |check| check[:valid] }

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
      # @param override_mode [String, nil] Override the configured validation mode (e.g. 'conservative' for RANGING/CHOPPY regimes)

      def get_validation_mode_config(override_mode: nil)
        signals_cfg = AlgoConfig.fetch[:signals] || {}
        mode = override_mode || signals_cfg[:validation_mode] || 'balanced'
        mode_config = signals_cfg.dig(:validation_modes, mode.to_sym) ||
                      signals_cfg.dig(:validation_modes, :balanced) || {}

        # Ensure mode_config is always a Hash (handle edge cases where config might be wrong type)
        mode_config = {} unless mode_config.is_a?(Hash)

        # Merge with mode name for logging
        mode_config.merge(mode: mode)
      end

      # Validate IV Rank - avoid extreme volatility conditions

      def analyze_primary_and_confirmation(index_cfg:, instrument:, signals_cfg:, primary_tf:, effective_timeframe:, confirmation_tf:, strategy_recommendation:)
        primary_analysis = if multi_indicator_enabled?(index_cfg, signals_cfg)
                             analyze_with_multi_indicators(
                               index_cfg: index_cfg,
                               instrument: instrument,
                               timeframe: primary_tf,
                               signals_cfg: signals_cfg
                             )
                           elsif strategy_recommendation
                             analyze_with_recommended_strategy(
                               index_cfg: index_cfg, instrument: instrument,
                               timeframe: effective_timeframe, strategy_recommendation: strategy_recommendation
                             )
                           else
                             supertrend_cfg = signals_cfg[:supertrend]
                             adx_cfg = signals_cfg[:adx] || {}
                             adx_min = signals_cfg.fetch(:enable_adx_filter, true) ? adx_cfg[:min_strength] : 0

                             analyze_timeframe(
                               index_cfg: index_cfg, instrument: instrument,
                               timeframe: primary_tf, supertrend_cfg: supertrend_cfg, adx_min_strength: adx_min
                             )
                           end

        unless primary_analysis[:status] == :ok
          Rails.logger.warn("[Signal] Primary timeframe analysis unavailable for #{index_cfg[:key]}: #{primary_analysis[:message]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end

        final_direction = primary_analysis[:direction]
        confirmation_analysis = nil

        if should_perform_confirmation?(confirmation_tf, signals_cfg, strategy_recommendation)
          mode_config = get_validation_mode_config
          adx_cfg = signals_cfg[:adx] || {}
          confirmation_adx_min = signals_cfg.fetch(:enable_adx_filter, true) ? (mode_config[:adx_confirmation_min_strength] || adx_cfg[:confirmation_min_strength] || adx_cfg[:min_strength]) : 0

          confirmation_analysis = analyze_timeframe(
            index_cfg: index_cfg, instrument: instrument, timeframe: confirmation_tf,
            supertrend_cfg: signals_cfg[:supertrend], adx_min_strength: confirmation_adx_min
          )

          if confirmation_analysis[:status] == :ok
            final_direction = multi_timeframe_direction(primary_analysis[:direction], confirmation_analysis[:direction])
          else
            Rails.logger.warn("[Signal] Confirmation timeframe analysis unavailable for #{index_cfg[:key]}: #{confirmation_analysis[:message]}")
            Signal::StateTracker.reset(index_cfg[:key])
            return nil
          end
        elsif confirmation_tf.present? && strategy_recommendation
          Rails.logger.info("[Signal] Skipping confirmation timeframe for #{index_cfg[:key]} (using strategy recommendation: #{strategy_recommendation[:strategy_name]})")
        end

        if final_direction == :avoid
          log_avoid_reason(index_cfg, strategy_recommendation)
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end
        # ===== END SMC DECISION ALIGNMENT =====

        { final_direction: final_direction, primary_analysis: primary_analysis, confirmation_analysis: confirmation_analysis }
      end

      def should_perform_confirmation?(confirmation_tf, signals_cfg, strategy_recommendation)
        confirmation_tf.present? && !strategy_recommendation && !multi_indicator_enabled?(nil, signals_cfg)
      end

      def log_avoid_reason(index_cfg, strategy_recommendation)
        if strategy_recommendation
          Rails.logger.info("[Signal] NOT proceeding for #{index_cfg[:key]}: #{strategy_recommendation[:strategy_name]} did not generate a signal (conditions not met)")
        else
          Rails.logger.info("[Signal] NOT proceeding for #{index_cfg[:key]}: multi-timeframe bias mismatch or weak trend")
        end
      end

      def direction_gate_blocked?(index_cfg, signals_cfg, final_direction, regime)
        return false unless signals_cfg.fetch(:enable_direction_gate, false)

        trade_side = final_direction == :bullish ? :CE : :PE

        if %w[RANGING CHOPPY INSUFFICIENT_DATA].include?(regime)
          Rails.logger.info("[Signal] DirectionGate BLOCKED #{index_cfg[:key]}: Market is #{regime}. Skipping to avoid theta decay.")
          return true
        end

        aligned = (regime == 'TRENDING_UP' && trade_side == :CE) || (regime == 'TRENDING_DOWN' && trade_side == :PE)
        unless aligned
          Rails.logger.info("[Signal] DirectionGate BLOCKED #{index_cfg[:key]}: Counter-trend trade. #{trade_side} requested vs #{regime}.")
          return true
        end

        Rails.logger.debug { "[Signal] DirectionGate ALLOWED #{index_cfg[:key]}: #{trade_side} in #{regime}" }
        false
      end

      def multi_indicator_enabled?(_index_cfg, signals_cfg)
        signals_cfg.fetch(:use_multi_indicator_strategy, false) && signals_cfg[:indicators].present?
      end

      def analyze_with_multi_indicators(index_cfg:, instrument:, timeframe:, signals_cfg:)
        indicator_configs = signals_cfg[:indicators] || []
        enabled_indicators = indicator_configs.select { |i| i[:enabled] }

        return { status: :error, message: "No enabled indicators" } if enabled_indicators.empty?

        interval = normalize_interval(timeframe)
        return { status: :error, message: "Invalid timeframe '#{timeframe}'" } if interval.blank?

        # Prepare indicator configs with per-index overrides if needed
        prepared_indicators = enabled_indicators.map do |ind|
          if ind[:type] == "adx" && (thresholds = index_cfg[:adx_thresholds])
            ind = ind.deep_dup
            ind[:config][:min_strength] = thresholds[:primary_min_strength] if thresholds[:primary_min_strength]
          end
          ind
        end

        begin
          series = instrument.candle_series(interval: interval)
          return { status: :no_data, message: "No candle data for #{timeframe}" } unless series
          strategy = MultiIndicatorStrategy.new(
            series: series,
            indicators: prepared_indicators,
            confirmation_mode: signals_cfg[:confirmation_mode],
            min_confidence: signals_cfg[:min_confidence]
          )

          signal = strategy.generate_signal(series.size - 1)

          # Map MultiIndicatorStrategy result to Engine's expected format
          direction = if signal
                        signal[:type] == :ce ? :bullish : :bearish
                      else
                        :avoid
                      end

          # Extract important indicator values for metadata/logic
          st_indicator = strategy.indicators.find { |i| i.is_a?(Indicators::SupertrendIndicator) }
          adx_indicator = strategy.indicators.find { |i| i.is_a?(Indicators::AdxIndicator) }

          st_result = st_indicator&.calculate_at(series.size - 1)
          adx_result = adx_indicator&.calculate_at(series.size - 1)

          {
            status: :ok,
            direction: direction,
            series: series,
            supertrend: st_result,
            adx_value: adx_result&.dig(:value),
            confluence: signal&.dig(:confluence),
            confidence: signal&.dig(:confidence),
            last_candle_timestamp: series.last.timestamp
          }
        rescue StandardError => e
          Rails.logger.error("[Signal] Multi-indicator analysis failed: #{e.message}")
          { status: :error, message: e.message }
        end
      end
      def normalize_interval(timeframe)
        return if timeframe.blank?

        cleaned = timeframe.to_s.strip.downcase
        digits = cleaned.gsub(/[^0-9]/, "")
        digits.presence
      end

      def validate_iv_rank(_index_cfg, series, mode_config = nil)
        mode_config = get_validation_mode_config(override_mode: mode_config) if mode_config.nil? || mode_config.is_a?(String) || mode_config.is_a?(Symbol)
        mode_config = get_validation_mode_config unless mode_config.is_a?(Hash)

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
        mode_config = get_validation_mode_config(override_mode: mode_config) if mode_config.nil? || mode_config.is_a?(String) || mode_config.is_a?(Symbol)
        mode_config = get_validation_mode_config unless mode_config.is_a?(Hash)

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

      # Validate trend confirmation with multiple signals

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

      def smc_zone_allows_entry?(direction, index_cfg, adx_value)
        zone = get_smc_zone(index_cfg)
        return true if zone == :equilibrium

        zone_override_adx = begin
                              AlgoConfig.fetch.dig(:signals, :smc, :zone_filter_adx_override).to_f
        rescue StandardError
                              30.0
        end

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

        # Rails.logger.debug { "[Signal] ADX check(#{timeframe_label}): value=#{adx_numeric}, min_required=#{min_required}" }

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

      private

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
        rescue StandardError => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
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
        return [{}, false, nil] unless AlgoConfig.fetch.dig(:market_context, :enabled) == true

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

      def record_signal_skip(signal, reason, stage: nil, code: nil)
        extra = {}
        extra['entry_skip_stage'] = stage.to_s if stage.present?
        extra['entry_skip_code'] = code.to_s if code.present?
        signal&.record_entry_outcome('skipped', reason, extra_metadata: extra.presence)
      end

      # =====================================================================
      # Pipeline stage methods extracted from run_for
      # =====================================================================

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

      def trading_context_blocked?(index_cfg, primary_series, primary_analysis, regime_result, regime_state, exit_testing_mode, signals_cfg)
        return false unless signals_cfg.fetch(:enable_trading_context_gate, true)
        return false if !regime_state || exit_testing_mode

        indicators = {
          adx_value: primary_analysis[:adx_value],
          regime_confidence: regime_result&.[](:confidence)
        }
        context = Context::Builder.call(
          market: primary_series,
          indicators: indicators,
          regime_state: regime_state,
          index_key: index_cfg[:key]
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

      def evaluate_entry_quality(index_cfg, primary_series, primary_analysis, final_direction, regime, exit_testing_mode)
        if exit_testing_mode
          Rails.logger.info("[Signal] Exit-testing mode: skipping EntryQualityFilter for #{index_cfg[:key]}")
          return { pass: true, score: 0, breakdown: {}, reject_reason: nil }
        end

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

      def execute_execution_gates(index_cfg, instrument, primary_series, final_direction, signals_cfg, exit_testing_mode)
        permission = :exit_testing
        smc_decision = final_direction == :bullish ? :call : :put

        if exit_testing_mode
          Rails.logger.info("[Signal] Exit-testing mode: skipping entry filter, permission/SMC gating, and momentum validation.")
          return { permission: permission, smc_decision: smc_decision, momentum_score: nil }
        end

        filter = Entries::EntryFilterEngine.new(series: primary_series, symbol: index_cfg[:key])
        unless filter.valid_entry?(direction: final_direction)
          Rails.logger.warn("[Signal] EntryFilterEngine BLOCKED #{index_cfg[:key]}: Missing Structure/Liquidity/Volatility alignment")
          Signal::StateTracker.reset(index_cfg[:key])
          return nil
        end
        Rails.logger.info("[Signal] EntryFilterEngine PASSED for #{index_cfg[:key]}")

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

      def execute_options_analysis(index_cfg, instrument, final_direction, primary_series, effective_validation_mode)
        expiry_blocked = expiry_trade_allowed?(index_cfg[:key]) == false
        expiry_date    = resolve_nearest_expiry_date(index_cfg: index_cfg, no_trade_gate: nil)
        chain_data     = expiry_date.present? ? instrument.fetch_option_chain(expiry_date) : nil

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
                             primary_series:, primary_tf:, entry_primary:, exit_testing_mode:,
                             diagnostic_metadata:, quality_result:, market_context_extra:, execution_permission:)
        supertrend_direct_entry = (entry_primary == 'supertrend') || exit_testing_mode

        entry_metadata = diagnostic_metadata.merge(market_context_extra).merge(
          entry_contract: supertrend_direct_entry ? 'supertrend_machine_v1' : 'bos_machine_v1',
          permission: execution_permission,
          entry_quality_score: quality_result[:score],
          entry_quality_breakdown: quality_result[:breakdown]
        )

        if supertrend_direct_entry
          Rails.logger.info("[Signal] Exit-testing mode: using direct EntryGuard path (no BOS state machine).") if exit_testing_mode
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

      def expiry_trade_allowed?(symbol)
        return true if exit_testing_mode?

        expiry_model = "Strategies::ExpiryModel".safe_constantize
        return true unless expiry_model

        expiry_model.trade_allowed?(symbol: symbol)
      rescue StandardError => e
        Rails.logger.error("[Signal] ExpiryModel unavailable (#{e.class}: #{e.message}); allowing trade")
        true
      end

      def exit_testing_mode?
        AlgoConfig.run_mode == 'exit_testing'
      end

      def effective_execution_permission(permission)
        return :scale_ready if permission.to_sym == :exit_testing

        permission
      end
    end
  end
end
# rubocop:enable Metrics/BlockNesting
