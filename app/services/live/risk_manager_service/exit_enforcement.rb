# frozen_string_literal: true

module Live
  class RiskManagerService
    module ExitEnforcement
      include Live::UnderlyingLtpResolver
      include Live::StructureInvalidationEvaluator

      # Lightweight struct for ETF position data (replaces OpenStruct for performance)
      EtfPositionData = Struct.new(
        :trend_score, :peak_trend_score, :adx, :atr_ratio,
        :underlying_price, :vwap, :is_long?
      )

      # Risk::Rules::* classes with no equivalent hardcoded check elsewhere in this
      # enforcement chain (as opposed to StructureInvalidationRule/PremiumMomentumFailureRule/
      # TimeStopRule/PercentagePnlRule, which are already wired individually below, or
      # PortfolioFloorRule/StopLossRule/TakeProfitRule/TrailingStopRule/TimeBasedExitRule/
      # EarlyTrendFailureRule/SmcNavigatorRule/SessionEndRule/EmergencyPeakLossRule, which
      # duplicate logic that already runs via UnifiedExitChecker/TrailingEngine/the enforce_*
      # methods in this file). Evaluated in the rules' own PRIORITY order, first exit wins.
      #
      # Several of these are enabled by shipped config the moment they're evaluated for the
      # first time — ZeroHwmFalseEntryRule (risk.zero_hwm_false_entry.enabled: true already
      # shipped), GreeksDecayExitRule/FastProfitLockRule/DteZeroThetaFlatExitRule (default
      # enabled with no config section to disable them). VixForceExitRule/IvCollapseRule/
      # SecureProfitRule/StructuralKillSwitchRule/GreenTradeCapRule stay off by default
      # (explicit config, or GreenTradeCapRule's own self-gating on unset thresholds).
      NOVEL_RULE_CLASSES = [
        Risk::Rules::VixForceExitRule,
        Risk::Rules::ZeroHwmFalseEntryRule,
        Risk::Rules::GreenTradeCapRule,
        Risk::Rules::IvCollapseRule,
        Risk::Rules::StructuralKillSwitchRule,
        Risk::Rules::DteZeroThetaFlatExitRule,
        Risk::Rules::GreeksDecayExitRule,
        Risk::Rules::FastProfitLockRule,
        Risk::Rules::SecureProfitRule
      ].freeze

      # Enforcement methods always accept an exit_engine keyword. They do not fetch positions from caller.
      # If exit_engine is provided, they will delegate the actual exit to it. Otherwise they call internal execute_exit.

      def enforce_hard_limits(exit_engine:)
        PositionTracker.active.find_each do |tracker|
          enforce_hard_limits_for(tracker, exit_engine: exit_engine)
        end
      end

      # Selling's exit surface: MaxPremiumLossRule (risk cap) then PremiumTargetRule
      # (take-profit). First-match-wins, same pattern as the buying enforcement layers.
      def enforce_selling_exits_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          tracker_snapshot: snapshot
        )

        [Risk::Rules::MaxPremiumLossRule, Risk::Rules::PremiumTargetRule].each do |rule_class|
          result = rule_class.new(config: risk_config).evaluate(context)
          next unless result.exit?

          exit_path = rule_class.name.demodulize.underscore
          Rails.logger.info("[RiskManager] #{result.reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, result.reason)
          dispatch_exit(exit_engine, tracker, result.reason)
          return
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_selling_exits_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # Evaluates NOVEL_RULE_CLASSES via RuleEngine (priority-ordered, first exit wins).
      # RuleEngine.evaluate already rescues per-rule errors internally, so one rule's bug
      # can't block the others from running.
      def novel_rule_engine
        @novel_rule_engine ||= Risk::Rules::RuleEngine.new(
          rules: NOVEL_RULE_CLASSES.map { |klass| klass.new(config: { enabled: true }) }
        )
      end

      def enforce_novel_rule_exits(exit_engine:)
        PositionTracker.active.find_each do |tracker|
          enforce_novel_rule_exits_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_novel_rule_exits_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          tracker_snapshot: snapshot
        )

        result = novel_rule_engine.evaluate(context)
        return unless result.exit?

        exit_path = result.rule_name || 'novel_rule'
        Rails.logger.info("[RiskManager] #{result.reason} for #{tracker.order_no} | Path: #{exit_path}")
        track_exit_path(tracker, exit_path, result.reason)
        dispatch_exit(exit_engine, tracker, result.reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_novel_rule_exits_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def enforce_hard_limits_for(tracker, exit_engine:)
        # UnifiedExitChecker handles Hard SL, TP, and Adaptive Trailing
        exit_decision = Live::UnifiedExitChecker.check_exit_conditions(tracker)

        if exit_decision && exit_decision[:exit]
          reason = "#{exit_decision[:reason]} (Hard Limit)"
          exit_path = exit_decision[:path] || 'hard_limit'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_hard_limits_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def enforce_early_trend_failure(exit_engine:)
        etf_cfg = begin
          resolved_risk_config[:etf] || {}
        rescue StandardError
          {}
        end

        return unless etf_cfg[:enabled]

        activation_profit = etf_cfg[:activation_profit_pct].to_f

        PositionTracker.active.find_each do |tracker|
          enforce_early_trend_failure_for(tracker, exit_engine: exit_engine, activation_profit: activation_profit)
        end
      end

      def enforce_early_trend_failure_for(tracker, exit_engine:, activation_profit: nil)
        activation_profit ||= (resolved_risk_config[:etf] || {})[:activation_profit_pct].to_f
        
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        pnl_pct = snapshot[:pnl_pct]
        return if pnl_pct.nil?

        # pnl_pct is decimal (e.g. 0.05 for 5%), convert to percentage for EarlyTrendFailure.applicable?
        pnl_pct_value = pnl_pct.to_f * 100.0
        # Config stores activation_profit_pct as decimal (0.07 = 7%); applicable? expects percentage
        activation_pct = activation_profit <= 1.0 ? activation_profit * 100.0 : activation_profit
        return unless Live::EarlyTrendFailure.applicable?(pnl_pct_value, activation_profit_pct: activation_pct)

        # Build position_data struct for ETF check
        instrument = tracker.instrument || tracker.watchable&.instrument
        return unless instrument

        # Get trend metrics
        series = begin
          instrument.candle_series(interval: '5')
        rescue StandardError
          nil
        end
        return unless series&.candles&.any?

        adx_value = begin
          instrument.adx(14, interval: '5')
        rescue StandardError
          nil
        end
        val = adx_value.is_a?(Hash) ? adx_value[:value] : adx_value
        return unless val

        trend_score = val.to_f + momentum_score(series.candles)
        peak_trend_score = tracker.meta&.dig('peak_trend_score') || trend_score
        
        # VWAP (simplified: use recent average price)
        vwap = series.candles.last(20).sum(&:close) / [series.candles.last(20).size, 1].max
        underlying_price = current_ltp(tracker) || tracker.entry_price.to_f

        position_data = EtfPositionData.new(
          trend_score: trend_score,
          peak_trend_score: peak_trend_score,
          adx: val,
          atr_ratio: calculate_atr_ratio(tracker),
          underlying_price: underlying_price,
          vwap: vwap,
          is_long?: %w[long_ce long_pe].include?(tracker.side)
        )

        if Live::EarlyTrendFailure.early_trend_failure?(position_data)
          reason = "EARLY_TREND_FAILURE (pnl: #{pnl_pct_value.round(2)}%)"
          exit_path = 'early_trend_failure'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_early_trend_failure_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def enforce_trailing_stops(exit_engine:)
        # Check if trailing is allowed in current time regime
        regime = Live::TimeRegimeService.instance.current_regime
        unless Live::TimeRegimeService.instance.allow_trailing?(regime)
          Rails.logger.debug { "[RiskManager] Trailing disabled for regime: #{regime}" }
          return
        end

        risk = risk_config
        drop_threshold = begin
          BigDecimal(risk[:exit_drop_pct].to_s)
        rescue StandardError
          BigDecimal(999) # Disabled by default
        end

        # Skip if trailing is disabled (threshold too high)
        return if drop_threshold >= 100

        PositionTracker.active.find_each do |tracker|
          enforce_dynamic_trailing_stops_for(tracker, exit_engine: exit_engine)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_trailing_stops method error: #{e.class} - #{e.message}")
      end

      def enforce_dynamic_trailing_stops_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        # TrailingEngine handles its own checks but we can filter here for efficiency
        return unless tracker.trade_state == 'expansion' || tracker.be_set?

        # TrailingEngine expects PositionData from ActiveCache
        cache = active_cache
        return unless cache

        position_data = cache.get_by_tracker_id(tracker.id)
        return unless position_data

        # engine = @trailing_engine ||= Live::TrailingEngine.new
        # process_tick handles peak updates and SL adjustments
        result = (@trailing_engine ||= Live::TrailingEngine.new).process_tick(position_data, exit_engine: exit_engine, tracker: tracker, pending_meta: pending_meta)

        if result[:exit_triggered]
          Rails.logger.info("[RiskManager] TrailingEngine triggered exit for #{tracker.order_no}: #{result[:reason]}")
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_dynamic_trailing_stops_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def advance_trade_states!
        PositionTracker.active.find_each do |tracker|
          advance_trade_state_for(tracker)
        end
      end

      def enforce_global_time_overrides(exit_engine:)
        # Global override 1: IV collapse detection
        enforce_iv_collapse_exit(exit_engine: exit_engine)

        # Global override 2: Price stall detection (especially after ₹2k)
        enforce_stall_detection_exit(exit_engine: exit_engine)
      end

      def enforce_iv_collapse_exit(exit_engine:)
        return unless iv_collapse_detection_enabled?

        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          # Check for sudden IV collapse
          # This would require IV data from option chain - for now, skip if not available
          # TODO: Implement IV collapse detection when IV data is available
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_iv_collapse_exit error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      def enforce_stall_detection_exit(exit_engine:)
        return unless stall_detection_enabled?

        PositionTracker.active.find_each do |tracker|
          enforce_stall_detection_exit_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_stall_detection_exit_for(tracker, exit_engine:)
        cfg = stall_detection_config
        stall_candles = cfg[:stall_candles] || 3
        min_profit_for_stall_check = BigDecimal((cfg[:min_profit_rupees] || 2000).to_s)

        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        pnl_rupees = snapshot[:pnl]
        return unless pnl_rupees && pnl_rupees >= min_profit_for_stall_check

        # Check if price has stalled (no new HH/LL for N candles)
        if price_stalled?(tracker, stall_candles)
          reason = "PRICE_STALL (#{stall_candles} candles no progress, profit: ₹#{pnl_rupees.round(2)})"
          exit_path = 'stall_detection'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_stall_detection_exit_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def enforce_time_based_exit(exit_engine:)
        PositionTracker.active.find_each do |tracker|
          enforce_time_based_exit_for(tracker, exit_engine: exit_engine)
        end
      end

      # EOD force-close: at or after market close, close all active positions.
      # Ensures intraday positions never carry overnight regardless of time-stop bypass or other rules.
      # For physical-settled instruments, force-close T-1 (day before expiry).
      def enforce_eod_force_close(exit_engine:)
        risk = risk_config
        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return unless market_close_time

        now = Time.current
        close_today = now >= market_close_time
        physical_t1_close = physical_settlement_t1_close?

        return unless close_today || physical_t1_close

        PositionTracker.active.find_each do |tracker|
          next if tracker.exit_requested_at.present? || tracker.exit_sent_at.present?

          reason = if physical_t1_close
                     "PHYSICAL_SETTLEMENT_T1 (EOD #{market_close_time.strftime('%H:%M')} IST)"
                   else
                     "MARKET_CLOSE (EOD #{market_close_time.strftime('%H:%M')} IST)"
                   end
          exit_path = physical_t1_close ? 'physical_settlement_t1' : 'eod_force_close'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_eod_force_close error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      def physical_settlement_t1_close?
        instrument = Instrument.find_by(settlement_type: 'physical')
        return false unless instrument

        today = Time.current.to_date
        PositionTracker.active
                      .where(expiry_date: today + 1)
                      .where.not(security_id: instrument.security_id)
                      .exists?
      rescue StandardError
        false
      end

      def trailing_armed_for?(tracker, position_data)
        trailing_cfg = AlgoConfig.fetch.dig(:risk, :trailing) || {}
        return false if trailing_cfg[:enabled] == false

        activation = (trailing_cfg[:activation_pct] || 0.025).to_f
        return false unless activation.positive?

        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return false unless entry_value.positive?

        peak_profit_pct = position_data.high_water_mark.to_f / entry_value
        peak_profit_pct >= activation
      rescue StandardError
        false
      end

      # LAYER 1: DYNAMIC TRAILING SL
      # Purpose: Move SL up-only to capture trend moves (direct trailing)
      def enforce_dynamic_trailing_stops(exit_engine:)
        cache = active_cache
        return unless cache

        PositionTracker.active.find_each do |tracker|
          enforce_dynamic_trailing_stops_for(tracker, exit_engine: exit_engine)
        end
      end

      # LAYER 2: STRUCTURE INVALIDATION
      # Purpose: Exit when trade thesis is broken by market structure failure
      def enforce_structure_invalidation(exit_engine:)
        return unless structure_invalidation_enabled?

        PositionTracker.active.find_each do |tracker|
          enforce_structure_invalidation_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_structure_invalidation_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          tracker_snapshot: snapshot
        )

        # Evaluate StructureInvalidationRule
        rule = Risk::Rules::StructureInvalidationRule.new(config: { enabled: true })
        result = rule.evaluate(context)

        if result.exit?
          reason = result.reason || 'STRUCTURE_INVALIDATION'
          exit_path = 'structure_invalidation'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_structure_invalidation_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def options_structure_invalidated_enforcement?(tracker, snapshot, si_cfg)
        min_hold = (si_cfg[:min_hold_seconds] || 120).to_i
        return false unless tracker.created_at && (Time.current - tracker.created_at) >= min_hold

        index_key = tracker.meta&.dig('index_key')
        underlying_ltp = resolve_underlying_ltp(index_key)
        return false unless underlying_ltp

        dual_condition_met?(tracker, underlying_ltp, snapshot[:ltp].to_f, si_cfg)
      end

      # LAYER 3: PREMIUM MOMENTUM FAILURE
      # Purpose: Kill dead option trades before theta eats them
      def enforce_premium_momentum_failure(exit_engine:)
        return unless premium_momentum_failure_enabled?

        PositionTracker.active.find_each do |tracker|
          enforce_premium_momentum_failure_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_premium_momentum_failure_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          tracker_snapshot: snapshot
        )

        # Evaluate PremiumMomentumFailureRule
        rule = Risk::Rules::PremiumMomentumFailureRule.new(config: { enabled: true })
        result = rule.evaluate(context)

        if result.exit?
          reason = result.reason || 'PREMIUM_MOMENTUM_FAILURE'
          exit_path = 'premium_momentum_failure'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_premium_momentum_failure_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # LAYER 4: TIME STOP
      # Purpose: Prevent holding dead trades - exit regardless of PnL when time limit exceeded
      def enforce_time_stop(exit_engine:)
        return unless time_stop_enabled?

        PositionTracker.active.find_each do |tracker|
          enforce_time_stop_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_time_stop_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          tracker_snapshot: snapshot
        )

        # Evaluate TimeStopRule
        rule = Risk::Rules::TimeStopRule.new(config: { enabled: true })
        result = rule.evaluate(context)

        if result.exit?
          reason = result.reason || 'TIME_STOP'
          exit_path = 'time_stop'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_time_stop_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # LAYER 5: RR-BASED PROFIT BOOKING
      # Purpose: Capture profits at pre-defined R multiples (e.g., 2R, 3R)
      def enforce_rr_profit_booking(exit_engine:)
        return unless rr_profit_booking_enabled?

        PositionTracker.active.find_each do |tracker|
          enforce_rr_profit_booking_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_rr_profit_booking_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        cfg = rr_profit_booking_config
        target_rr = (cfg[:target_rr] || 2.0).to_f

        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        pnl_pct = snapshot[:pnl_pct]
        return if pnl_pct.nil?

        # Get initial risk (SL) from tracker meta or default
        sl_pct = tracker.meta&.dig('initial_sl_pct')&.to_f

        # Fallback: if premium_stop_price exists, calculate sl_pct from it
        if sl_pct.nil? || sl_pct.zero?
          premium_stop = tracker.meta&.dig('premium_stop_price')&.to_f
          if premium_stop&.positive?
            entry = tracker.entry_price.to_f
            sl_pct = ((entry - premium_stop) / entry).abs * 100.0
          end
        end

        # Second fallback: use global default SL pct
        # risk_config[:sl_pct] is DECIMAL (e.g. 0.12 for 12%) - convert to PERCENTAGE for RR formula
        sl_pct ||= (pct_value(risk_config[:sl_pct] || 0.10).to_f * 100.0)

        return if sl_pct.zero?

        # RR = Profit% / SL%
        # pnl_pct is decimal (e.g. 0.05 for 5%), convert to percentage for RR calculation
        pnl_pct_value = pnl_pct.to_f * 100.0
        current_rr = pnl_pct_value / sl_pct

        if current_rr >= target_rr
          reason = "RR_PROFIT_BOOKING (RR: #{current_rr.round(2)}, Target: #{target_rr}, PnL: #{(pnl_pct.to_f * 100).round(2)}%, SL: #{sl_pct.round(2)}%)"
          exit_path = 'rr_profit_booking'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_rr_profit_booking_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # LAYER 4.5: PERCENTAGE-BASED PNL EXIT
      # Purpose: Full exit when target % PnL is reached (independent of initial risk)
      def enforce_percentage_pnl_exit(exit_engine:)
        cfg = risk_config[:percentage_pnl_exit] || {}
        return unless cfg[:enabled]

        PositionTracker.active.find_each do |tracker|
          enforce_percentage_pnl_exit_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_percentage_pnl_exit_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config,
          tracker_snapshot: snapshot
        )

        # Evaluate PercentagePnlRule
        rule = Risk::Rules::PercentagePnlRule.new(config: risk_config)
        result = rule.evaluate(context)

        if result.exit?
          reason = result.reason || 'PERCENTAGE_PNL_EXIT'
          exit_path = 'percentage_pnl_exit'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_percentage_pnl_exit_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # Profit-Floor enforcement (stateful guarantee).
      def enforce_profit_floor(exit_engine:)
        cfg = profit_floor_config
        return unless cfg[:enabled]

        PositionTracker.active.find_each do |tracker|
          enforce_profit_floor_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_profit_floor_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        cfg = profit_floor_config
        return unless cfg[:enabled]

        position_data ||= active_cache&.get_by_tracker_id(tracker.id)

        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        net_pnl = safe_big_decimal(snapshot[:pnl])
        return unless net_pnl

        lock_pct = cfg[:lock_pct]
        lock_rupees_static = cfg[:lock_rupees]
        breakeven_at = cfg[:breakeven_at]
        time_kill_minutes = cfg[:time_kill_minutes]
        exit_fee = BrokerFeeCalculator.fee_per_order

        # Compute lock threshold (lock_pct is DECIMAL, e.g. 0.10 for 10%)
        lock_rupees = if lock_pct
                        capital = safe_big_decimal(snapshot[:capital_deployed])
                        capital&.positive? ? (capital * BigDecimal(lock_pct.to_s)).ceil : lock_rupees_static
                      else
                        lock_rupees_static
                      end

        mark_breakeven_reached!(tracker, net_pnl, threshold_rupees: breakeven_at) if breakeven_at
        arm_profit_floor!(tracker, net_pnl, lock_rupees: lock_rupees) if lock_rupees
 
        # Ratchet the floor upward as HWM PnL grows (trailing floor).
        trail_pct = cfg[:trail_pct]
        if trail_pct && position_data && (pending_meta || tracker.meta || {})['profit_floor_rupees'].present?
          hwm_pnl = safe_big_decimal(position_data.high_water_mark)
          update_trailing_floor!(tracker, hwm_pnl, trail_pct: trail_pct, pending_meta: pending_meta)
        end
 
        floor = (pending_meta || tracker.meta || {})['profit_floor_rupees'] || tracker.profit_floor_rupees
        return unless floor

        if profit_floor_time_kill?(tracker, time_kill_minutes: time_kill_minutes, pending_meta: pending_meta)
          reason = "PROFIT_FLOOR_TIME_KILL (floor: ₹#{floor}, age_min: #{time_kill_minutes})"
          exit_path = 'profit_floor_time_kill'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
          return
        end

        threshold = BigDecimal(floor.to_s) + BigDecimal(exit_fee.to_s)
        return unless net_pnl <= threshold

        final_net_pnl = net_pnl - BigDecimal(exit_fee.to_s)
        reason = "PROFIT_FLOOR_LOCK (Current net: ₹#{net_pnl.round(2)}, Net after exit: ₹#{final_net_pnl.round(2)}, floor: ₹#{floor})"
        exit_path = 'profit_floor_lock'
        Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
        track_exit_path(tracker, exit_path, reason)
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_profit_floor_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # LAYER 0: Hard Premium SL
      def enforce_premium_r_stop(exit_engine:)
        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_premium_r_stop_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_premium_r_stop_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        # Skip R-stop when trailing system has taken ownership
        if trailing_armed_for?(tracker, position_data)
          return
        end
 
        ltp = position_data.current_ltp
        return unless ltp
 
        premium_stop = (pending_meta || tracker.meta || {})['premium_stop_price']
        return unless premium_stop

        if ltp.to_f <= premium_stop.to_f
          reason = "PREMIUM_R_STOP (ltp: #{ltp}, stop: #{premium_stop})"
          exit_path = 'premium_r_stop'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_premium_r_stop_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def price_stalled?(tracker, stall_candles)
        # Get recent LTP history
        ltp_history = get_ltp_history_for_stall_check(tracker, stall_candles + 1)
        return false if ltp_history.size < stall_candles + 1

        # Check if LTP has made no progress (no new HH for long positions)
        recent_ltps = ltp_history.last(stall_candles + 1).map { |h| h[:ltp].to_f }
        current_ltp = recent_ltps.last
        previous_high = recent_ltps.first(stall_candles).max

        # If current LTP is not making new highs (within 1% tolerance), consider stalled
        tolerance = 0.01 # 1% tolerance
        current_ltp <= previous_high * (1 + tolerance)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] price_stalled? error: #{e.class} - #{e.message}")
        false
      end

      def get_ltp_history_for_stall_check(tracker, lookback_candles)
        # Get LTP history from Redis cache or tracker
        cache_key = "position:ltp_history:#{tracker.id}"
        cached = Rails.cache.read(cache_key)

        unless cached
          # Build from recent Redis PnL cache entries
          redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
          cached = if redis_pnl && redis_pnl[:ltp]
                     [{ ltp: redis_pnl[:ltp], timestamp: redis_pnl[:timestamp] || Time.current.to_i }]
                   else
                     []
                   end
        end

        # Update with current LTP
        snapshot = pnl_snapshot(tracker)
        current_ltp = snapshot&.dig(:ltp) || tracker.tradable&.ltp
        if current_ltp
          cached = (cached || []).last(lookback_candles - 1)
          cached << { ltp: current_ltp, timestamp: Time.current.to_i }
          Rails.cache.write(cache_key, cached, expires_in: 1.hour)
        end

        cached || []
      rescue StandardError => e
        Rails.logger.error("[RiskManager] get_ltp_history_for_stall_check error: #{e.class} - #{e.message}")
        []
      end

      def enforce_time_based_exit_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        risk = risk_config
        exit_time = parse_time_hhmm(risk[:time_exit_hhmm] || '15:20')
        return unless exit_time

        now = Time.current
        return unless now >= exit_time

        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return if market_close_time && now >= market_close_time

        tracker.hydrate_pnl_from_cache!
        if tracker.last_pnl_rupees.present? && tracker.last_pnl_rupees.positive?
          min_profit = begin
            BigDecimal((risk[:min_profit_rupees] || 0).to_s)
          rescue StandardError
            BigDecimal(0)
          end
          if min_profit.positive? && tracker.last_pnl_rupees < min_profit
            Rails.logger.info("[RiskManager] Time-based exit skipped for #{tracker.order_no} - PnL < min_profit")
            return
          end
        end

        reason = "time-based exit (#{exit_time.strftime('%H:%M')})"
        exit_path = 'time_based'
        Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
        track_exit_path(tracker, exit_path, reason)
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_time_based_exit_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def advance_trade_state_for(tracker, position_data: nil, pending_meta: nil)
        # Use passed position_data or fetch from ActiveCache if not provided
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data
 
        entry_risk_rupees = (pending_meta || tracker.meta || {})['entry_risk_rupees']
        risk_value = safe_big_decimal(entry_risk_rupees)
 
        # Ensure we always update peak trend score if possible
        update_peak_trend_score(tracker, position_data, pending_meta: pending_meta)

        return unless risk_value&.positive?

        net_pnl = safe_big_decimal(position_data.pnl)
        return unless net_pnl

        current_r = (net_pnl / risk_value).to_f

        if tracker.trade_state.blank?
          tracker.update_column(:trade_state, 'init') # rubocop:disable Rails/SkipsModelValidations
        end

        case tracker.trade_state
        when 'init'
          if current_r >= 1.0
            tracker.update_columns(trade_state: 'validated', validated_at: Time.current)
          end
        when 'validated'
          if current_r >= 2.0
            tracker.update_columns(trade_state: 'expansion', expansion_at: Time.current)
          end
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] advance_trade_state_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # Helper: Calculate ATR from candles
      def calculate_atr(candles)
        return 0.0 if candles.size < 2

        true_ranges = []
        candles.each_cons(2) do |prev, curr|
          tr1 = curr.high - curr.low
          tr2 = (curr.high - prev.close).abs
          tr3 = (curr.low - prev.close).abs
          true_ranges << [tr1, tr2, tr3].max
        end

        return 0.0 if true_ranges.empty?
        true_ranges.sum / true_ranges.size
      end

      def update_peak_trend_score(tracker, position_data, pending_meta: nil)
        begin
          # Use trend score from position_data if available (from ActiveCache)
          trend_score = position_data.respond_to?(:underlying_trend_score) ? position_data.underlying_trend_score : nil
          
          # Fallback to calculation only if not in position_data
          if trend_score.nil?
            instrument = tracker.instrument || tracker.watchable&.instrument
            return unless instrument
          end
          
          peak = (pending_meta || tracker.meta || {})['peak_trend_score'] || 0
          if trend_score > peak
            if pending_meta
              pending_meta['peak_trend_score'] = trend_score
            else
              meta = tracker.meta || {}
              meta['peak_trend_score'] = trend_score
              tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
            end
          end
        rescue StandardError
          nil
        end
      end

      # Calculate momentum score from candles (0-50 range)
      def momentum_score(candles)
        return 0 if candles.size < 3

        recent = candles.last(3)
        return 0 if recent.size < 2

        # Simple momentum: price change direction and magnitude
        price_change = (recent.last.close - recent.first.close) / recent.first.close
        volume_factor = if recent.last.respond_to?(:volume) && recent.last.volume
                          [recent.last.volume / 1_000_000.0,
                           1.0].min
                        else
                          0.5
                        end

        # Return a simple momentum indicator (0-50 range)
        ((price_change.abs * 25) + (volume_factor * 25)).round.clamp(0, 50)
      end

      def mark_breakeven_reached!(tracker, net_pnl, threshold_rupees:)
        begin
          return if tracker.be_set?
          return unless BigDecimal(threshold_rupees.to_s) <= net_pnl

          tracker.update!(be_set: true)
        rescue StandardError => e
          Rails.logger.warn("[RiskManager] mark_breakeven_reached! failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        end
      end

      def arm_profit_floor!(tracker, net_pnl, lock_rupees:)
        return if tracker.profit_floor_rupees.present?
        return unless BigDecimal(lock_rupees.to_s) <= net_pnl

        tracker.update!(
          profit_floor_rupees: Integer(lock_rupees),
          profit_floor_set_at: Time.current
        )
        Rails.logger.info("[RiskManager] Profit floor armed for #{tracker.order_no}: ₹#{lock_rupees}")
      rescue StandardError => e
        Rails.logger.error("[RiskManager] arm_profit_floor! failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end

      def profit_floor_time_kill?(tracker, time_kill_minutes:, pending_meta: nil)
        begin
          return false unless time_kill_minutes
          
          floor_set_at = (pending_meta || tracker.meta || {})['profit_floor_set_at'] || tracker.profit_floor_set_at
          return false unless floor_set_at
  
          (Time.current - floor_set_at) >= time_kill_minutes.minutes
        rescue StandardError
          false
        end
      end

      def update_trailing_floor!(tracker, hwm_pnl, trail_pct:, pending_meta: nil)
        return unless hwm_pnl&.positive?

        # floor = max(current_floor, hwm_pnl * trail_pct) — ratchet upward only, never down.
        current_floor = (pending_meta || tracker.meta || {})['profit_floor_rupees'].to_i
        dynamic_floor = (hwm_pnl * BigDecimal(trail_pct.to_s)).to_i
        return unless dynamic_floor > current_floor

        # profit_floor_rupees is stored in meta (store_accessor), not a DB column
        if pending_meta
          pending_meta['profit_floor_rupees'] = dynamic_floor.to_i
        else
          meta = (tracker.meta || {}).stringify_keys
          meta['profit_floor_rupees'] = dynamic_floor.to_i
          tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
        end

        Rails.logger.info(
          "[RiskManager] Trailing floor raised for #{tracker.order_no}: " \
          "₹#{current_floor} → ₹#{dynamic_floor} (HWM: ₹#{hwm_pnl.round(2)}, trail: #{(trail_pct * 100).round}%)"
        )
      rescue StandardError => e
        Rails.logger.error("[RiskManager] update_trailing_floor! failed for #{tracker.order_no}: #{e.message}")
      end

      def build_position_data_for_rule_engine(tracker, snapshot)
        # Build PositionData compatible with RuleContext
        instrument = tracker.instrument || tracker.watchable&.instrument
        index_key = tracker.meta&.dig('index_key') || instrument&.symbol_name

        Positions::PositionData.new(
          tracker_id: tracker.id,
          security_id: tracker.security_id,
          segment: tracker.segment || instrument&.exchange_segment,
          entry_price: tracker.entry_price,
          quantity: tracker.quantity,
          current_ltp: snapshot[:ltp],
          pnl: snapshot[:pnl],
          pnl_pct: snapshot[:pnl_pct],
          high_water_mark: snapshot[:hwm_pnl],
          peak_profit_pct: calculate_peak_profit_pct(tracker, snapshot),
          position_direction: Positions::MetadataResolver.direction(tracker),
          index_key: index_key,
          underlying_segment: instrument&.exchange_segment,
          underlying_security_id: instrument&.security_id,
          underlying_symbol: index_key
        )
      end

      def calculate_peak_profit_pct(tracker, snapshot)
        hwm = snapshot[:hwm_pnl]
        return nil unless hwm&.positive?

        entry_price = tracker.entry_price
        quantity = tracker.quantity
        return nil unless entry_price && quantity&.positive?

        buy_value = entry_price * quantity
        return nil unless buy_value.positive?

        return (hwm / buy_value).to_f
      end
    end
  end
end
