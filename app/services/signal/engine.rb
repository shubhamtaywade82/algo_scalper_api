# frozen_string_literal: true

module Signal
  # Stock Supertrend options-buying pipeline: 1m flip → chop gate → ATM strike → EntryGuard.
  class Engine
    class << self
      def run_for(index_cfg)
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
        quality_result = stock_quality_result
        permission = :scale_ready
        smc_decision = final_direction == :bullish ? :call : :put

        nearest_expiry = resolve_nearest_expiry_date(index_cfg: index_cfg)
        if entry_dte_guard_blocks?(index_cfg: index_cfg, signals_cfg: signals_cfg, nearest_expiry: nearest_expiry)
          Signal::StateTracker.reset(index_cfg[:key])
          record_cycle_block!("entry_dte_guard", regime: regime, direction: final_direction)
          return summary
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
        unless validation_result[:valid]
          Rails.logger.warn("[Signal] NOT proceeding for #{index_cfg[:key]}: #{validation_result[:reason]}")
          Signal::StateTracker.reset(index_cfg[:key])
          return
        end

        Rails.logger.info("[Signal] Proceeding with #{final_direction} signal for #{index_cfg[:key]}")

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
        end
        # ===== END SMC DECISION ALIGNMENT =====

        # Get state snapshot first for signal persistence
        state_snapshot = Signal::StateTracker.record(
          index_key: index_cfg[:key],
          direction: final_direction,
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          config: signals_cfg
        )

        options_analysis = execute_options_analysis(
          index_cfg,
          expiry_date: nearest_expiry,
          expiry_blocked: expiry_trade_allowed?(index_cfg[:key]) == false
        )

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

        TradingSignal.create_from_analysis(
          index_key: index_cfg[:key],
          direction: final_direction.to_s,
          timeframe: effective_timeframe,
          supertrend_value: primary_analysis[:supertrend][:last_value],
          adx_value: primary_analysis[:adx_value],
          candle_timestamp: primary_analysis[:last_candle_timestamp],
          confidence_score: confidence_score,
          metadata: {
            # Clear path tracking for analysis
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
            # SMC integration
            smc_decision: smc_decision.to_s,
            smc_permission: permission.to_s
          }
        )

        if signals_cfg.dig(:setup_validator, :enabled)
          validator = SetupValidator.new(
            underlying: index_cfg[:key],
            direction: final_direction,
            series: primary_analysis[:series],
            supertrend_result: primary_analysis[:supertrend],
            index_cfg: index_cfg
          )
          setup_result = validator.valid?
          unless setup_result.valid
            Rails.logger.info("[Signal] SetupValidator blocked #{index_cfg[:key]}: #{setup_result.reason}")
            record_signal_skip(signal, setup_result.reason, stage: "setup_validator", code: setup_result.reason)
            Signal::StateTracker.reset(index_cfg[:key])
            record_cycle_block!("setup_validator", regime: regime, direction: final_direction)
            return summary
          end
          diagnostic_metadata[:iv_percentile] = setup_result.metadata[:iv_percentile]
          diagnostic_metadata[:momentum_score] = setup_result.metadata[:momentum_score]
        end

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

        picks = Options::ChainAnalyzer.pick_strikes_with_qualification(
          index_cfg: index_cfg,
          direction: final_direction,
          permission: permission,
          expected_spot_move: expected_spot_move
        )
        # ===== END STRIKE QUALIFICATION LAYER =====

        entered = trigger_entry_flow(
          index_cfg: index_cfg,
          signal: signal,
          picks: gate_result[:picks],
          final_direction: final_direction,
          primary_series: primary_series,
          primary_tf: primary_tf,
          diagnostic_metadata: diagnostic_metadata,
          quality_result: quality_result,
          execution_permission: permission
        )
        if entered
          summary.entered!(direction: final_direction, regime: regime)
        else
          record_cycle_block!("entry_guard", regime: regime, direction: final_direction)
        end
        summary
      rescue StandardError => e
        Rails.logger.fatal("[FATAL_SIGNAL_ERROR] #{e.class}: #{e.message}\n#{e.backtrace.first(10).join(%(\n))}")
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

        Rails.logger.info(
          "\n\n[Signal] ----------------------------------------------------- " \
          "Starting analysis for #{index_cfg[:key]} (IDX_I) " \
          "--------------------------------------------------------"
        )
        true
      end

        # Prepare entry metadata to pass to EntryGuard
        entry_metadata = {
          entry_path: entry_path,
          strategy: strategy_recommendation&.dig(:strategy_name) || 'supertrend_adx',
          strategy_mode: use_strategy_recommendations ? 'recommended' : 'supertrend_adx',
          primary_timeframe: primary_tf,
          effective_timeframe: effective_timeframe,
          confirmation_timeframe: confirmation_tf,
          confirmation_enabled: enable_confirmation,
          validation_mode: signals_cfg[:validation_mode] || 'balanced',
          permission: permission
        }

        picks.each_with_index do |pick, _index|
          # Rails.logger.info("[Signal] Attempting entry #{index + 1}/#{picks.size} for #{index_cfg[:key]}: #{pick[:symbol]} (scale x#{state_snapshot[:multiplier]})")
          result = Entries::EntryGuard.try_enter(
            index_cfg: index_cfg,
            pick: pick,
            direction: final_direction,
            scale_multiplier: state_snapshot[:multiplier],
            entry_metadata: entry_metadata,
            permission: permission
          )
          Signal::StateTracker.reset(index_cfg[:key])
          record_cycle_block!("analysis_unavailable")
          return
        end

        trend_direction = SupertrendTrend.direction(
          series: primary_analysis[:series],
          supertrend_result: primary_analysis[:supertrend]
        )
        if trend_direction == :none
          Rails.logger.info("[Signal] SupertrendTrend :none — no trade for #{index_cfg[:key]}")
          Signal::StateTracker.reset(index_cfg[:key])
          record_cycle_block!("supertrend_none")
          return
        end

          if result
            # Rails.logger.info("[Signal] Entry successful for #{index_cfg[:key]}: #{pick[:symbol]}")
          else
            Rails.logger.debug { "[Signal] Entry failed for #{index_cfg[:key]}: #{pick[:symbol]} #{result}" }
          end
        end

        {
          direction: final_direction,
          primary_analysis: primary_analysis,
          primary_series: primary_analysis[:series],
          regime: :trending,
          validation_result: { valid: true },
          effective_validation_mode: "stock"
        }
      end

      def stock_quality_result
        { pass: true, score: 100, breakdown: { stock_mode: true } }
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

      def get_smc_bias_direction(index_cfg)
        instrument = Instrument.find_by(tradingsymbol: index_cfg[:key])
        return :neutral unless instrument

        decision = Smc::BiasEngine.new(instrument).decision
        case decision
        when :call then :bullish
        when :put then :bearish
        else :neutral
        end
      rescue StandardError
        :neutral
      end

      def calculate_confidence_score(primary_analysis:, validation_result:, index_cfg: nil)
        base_confidence = 0.5
        adx_factor = adx_confidence_factor(primary_analysis[:adx_value])
        validation_factor = validation_result[:valid] ? 0.1 : 0.0
        supertrend_factor = supertrend_confidence_factor(primary_analysis[:supertrend])

        direction = primary_analysis[:direction]
        series = primary_analysis[:series]
        macd_factor = series && direction ? macd_confidence_factor(direction, series) : 0.0
        smc_factor = index_cfg && direction ? smc_bias_confidence_factor(direction, index_cfg) : 0.0

        capped = [base_confidence + adx_factor + validation_factor + supertrend_factor + macd_factor + smc_factor, 1.0].min
        return capped if validation_result[:valid]

        [capped, 0.79].min
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

      # Validate market timing - avoid problematic trading times
      def validate_market_timing
        # TODO: Implement market timing validation if needed
        current_time = Time.zone.now

        expiry_model.trade_allowed?(symbol: symbol)
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

      def dynamic_config_enabled?
        AlgoConfig.fetch.dig(:signals, :use_optimized_params) != false
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

        params = optimized.params.symbolize_keys
        base_cfg[:period] = params[:atr_period] if params[:atr_period]
        base_cfg[:base_multiplier] = params[:multiplier] if params[:multiplier]
        base_cfg
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
        rescue StandardError => e
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
    end
  end
end
