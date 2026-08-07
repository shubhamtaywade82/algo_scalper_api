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

            if Signal::ConfigResolver.multi_indicator_enabled?(signals_cfg)
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
            mode_config = Signal::ConfigResolver.validation_mode_config
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

            validation_result = Signal::ValidationGates.comprehensive_validation(index_cfg, final_direction, primary_series,
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
        if Signal::ValidationGates.trading_context_blocked?(index_cfg, primary_series, primary_analysis, regime_result, regime_state, exit_testing_mode, signals_cfg)
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
            smc_decision = Signal::SmcDecisionResolver.get_smc_decision(index_cfg, instrument, signals_cfg, final_direction)
            unless Signal::SmcDecisionResolver.smc_decision_aligned?(smc_decision, final_direction)
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
        entry_path = Signal::EntryPathIdentifier.build(
          strategy_recommendation: strategy_recommendation,
          use_strategy_recommendations: use_strategy_recommendations,
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
        if Signal::ExpiryGate.expiry_trade_allowed?(index_cfg[:key]) == false
          Rails.logger.info("[Signal] ExpiryModel BLOCKED #{index_cfg[:key]}: Midday decay period")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end
        # ===== END EXPIRY DAY SESSION FILTER =====

        # ===== GAMMA RAMP DETECTION =====
        # Detect if price is approaching an OI cluster for explosive potential
        expiry_date = Signal::ExpiryGate.resolve_nearest_expiry_date(index_cfg: index_cfg, no_trade_gate: nil)
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

        strike_result = Options::ChainAnalyzer.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: final_direction,
          permission: execution_permission,
          expected_spot_move: expected_spot_move,
          momentum_score: momentum_score
        )
        # ===== END STRIKE QUALIFICATION LAYER =====

        picks = strike_result.picks
        if picks.blank?
          skip_reason = strike_result.failure_reason.presence || 'No suitable option strikes'
          Rails.logger.warn("[Signal] No suitable option strikes found for #{index_cfg[:key]} #{final_direction}: #{skip_reason}")
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
        validation_result = Signal::ValidationGates.comprehensive_validation(
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

      def execute_options_analysis(index_cfg, instrument, final_direction, primary_series, effective_validation_mode)
        expiry_blocked = Signal::ExpiryGate.expiry_trade_allowed?(index_cfg[:key]) == false
        expiry_date    = Signal::ExpiryGate.resolve_nearest_expiry_date(index_cfg: index_cfg, no_trade_gate: nil)
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

        iv_rank_result    = Signal::ValidationGates.validate_iv_rank(index_cfg, primary_series, effective_validation_mode)
        theta_risk_result = Signal::ValidationGates.validate_theta_risk(index_cfg, final_direction, effective_validation_mode)

        {
          gamma_pressure: gamma_pressure_result,
          iv_rank: iv_rank_result,
          theta_risk: theta_risk_result,
          expiry_blocked: expiry_blocked,
          expiry_date: expiry_date,
          chain_data: chain_data
        }
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
