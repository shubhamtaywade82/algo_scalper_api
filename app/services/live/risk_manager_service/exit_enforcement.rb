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

      # Enforcement methods always accept an exit_engine keyword. They do not fetch positions from caller.
      # If exit_engine is provided, they will delegate the actual exit to it. Otherwise they call internal execute_exit.

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
        PositionTracker.active.find_each do |tracker|
          enforce_dynamic_trailing_stops_for(tracker, exit_engine: exit_engine)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_trailing_stops method error: #{e.class} - #{e.message}")
      end

      def enforce_dynamic_trailing_stops_for(tracker, exit_engine:)
        # TrailingEngine handles its own checks but we can filter here for efficiency
        return unless tracker.trade_state == 'expansion' || tracker.be_set?

        # TrailingEngine expects PositionData from ActiveCache
        cache = active_cache
        return unless cache

        position_data = cache.get_by_tracker_id(tracker.id)
        return unless position_data

        # engine = @trailing_engine ||= Live::TrailingEngine.new
        # process_tick handles peak updates and SL adjustments
        result = (@trailing_engine ||= Live::TrailingEngine.new).process_tick(position_data, exit_engine: exit_engine)

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

      def advance_trade_state_for(tracker)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        entry_risk_rupees = tracker.meta&.dig('entry_risk_rupees')
        risk_value = safe_big_decimal(entry_risk_rupees)

        # Ensure we always update peak trend score if possible
        update_peak_trend_score(tracker, snapshot)

        return unless risk_value&.positive?

        net_pnl = safe_big_decimal(snapshot[:pnl])
        return unless net_pnl

        current_r = (net_pnl / risk_value).to_f

        if tracker.trade_state.blank?
          tracker.update_column(:trade_state, 'init') # rubocop:disable Rails/SkipsModelValidations
        end

        case tracker.trade_state
        when 'init'
          if current_r >= 1.0
            tracker.update_columns(trade_state: 'validated', validated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          end
        when 'validated'
          if current_r >= 2.0
            tracker.update_columns(trade_state: 'expansion', expansion_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          end
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] advance_trade_state_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      private

      def update_peak_trend_score(tracker, snapshot)
        instrument = tracker.instrument || tracker.watchable&.instrument
        return unless instrument

        # Calculate current trend score
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

        peak = tracker.meta&.dig('peak_trend_score') || 0
        if trend_score > peak
          meta = tracker.meta || {}
          meta['peak_trend_score'] = trend_score
          tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
        end
      rescue StandardError
        nil
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
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_time_based_exit error: #{e.class} - #{e.message}")
      end

      # EOD force-close: at or after market close, close all active positions.
      # Ensures intraday positions never carry overnight regardless of time-stop bypass or other rules.
      def enforce_eod_force_close(exit_engine:)
        risk = risk_config
        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return unless market_close_time

        now = Time.current
        return unless now >= market_close_time

        PositionTracker.active.find_each do |tracker|
          next if tracker.exit_requested_at.present? || tracker.exit_sent_at.present?

          reason = "MARKET_CLOSE (EOD #{market_close_time.strftime('%H:%M')} IST)"
          exit_path = 'eod_force_close'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_eod_force_close error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      def enforce_time_based_exit_for(tracker, exit_engine:)
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

      def enforce_premium_r_stop(exit_engine:)
        PositionTracker.active.find_each do |tracker|
          enforce_premium_r_stop_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_premium_r_stop_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Skip R-stop when trailing system has taken ownership
        if trailing_armed_for?(tracker, snapshot)
          Rails.logger.debug do
            "[RiskManager] PREMIUM_R_STOP suppressed for #{tracker.order_no} — trailing armed"
          end
          return
        end

        ltp = snapshot[:ltp]
        return unless ltp

        premium_stop = tracker.meta&.dig('premium_stop_price')
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

      def trailing_armed_for?(tracker, snapshot)
        trailing_cfg = AlgoConfig.fetch.dig(:risk, :trailing) || {}
        return false if trailing_cfg[:enabled] == false

        activation = (trailing_cfg[:activation_pct] || 0.025).to_f
        return false unless activation.positive?

        entry_value = tracker.entry_price.to_f * tracker.quantity.to_i
        return false unless entry_value.positive?

        peak_profit_pct = snapshot[:hwm_pnl].to_f / entry_value
        peak_profit_pct >= activation
      rescue StandardError
        false
      end

      # LAYER 1: DYNAMIC TRAILING SL
      # Purpose: Move SL up-only to capture trend moves (direct trailing)
      def enforce_dynamic_trailing_stops(exit_engine:)
        engine = @trailing_engine ||= Live::TrailingEngine.new
        cache = active_cache
        return unless cache

        PositionTracker.active.find_each do |tracker|
          # TrailingEngine expects PositionData from ActiveCache
          position_data = cache.get_by_tracker_id(tracker.id)
          next unless position_data

          # process_tick handles peak updates and SL adjustments
          result = engine.process_tick(position_data, exit_engine: exit_engine)

          if result[:exit_triggered]
            Rails.logger.info("[RiskManager] TrailingEngine triggered exit for #{tracker.order_no}: #{result[:reason]}")
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_dynamic_trailing_stops error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
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

        si_cfg = (risk_config[:exits] || {})[:structure_invalidation] || {}

        if si_cfg[:underlying_move_pct] && si_cfg[:premium_drop_pct]
          return unless options_structure_invalidated_enforcement?(tracker, snapshot, si_cfg)

          reason = 'STRUCTURE_INVALIDATION (dual: underlying move + premium drop)'
          exit_path = 'structure_invalidation'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
          return
        end

        # Legacy rule-engine path
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )

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

      def enforce_premium_momentum_failure_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
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

      def enforce_time_stop_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
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

      def enforce_rr_profit_booking_for(tracker, exit_engine:)
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

      def enforce_percentage_pnl_exit_for(tracker, exit_engine:)
        snapshot = pnl_snapshot(tracker)
        return unless snapshot

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
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

      def enforce_profit_floor_for(tracker, exit_engine:)
        cfg = profit_floor_config
        return unless cfg[:enabled]

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
        if trail_pct && tracker.profit_floor_rupees.present?
          hwm_pnl = safe_big_decimal(snapshot[:hwm_pnl])
          update_trailing_floor!(tracker, hwm_pnl, trail_pct: trail_pct)
        end

        floor = tracker.profit_floor_rupees
        return unless floor

        if profit_floor_time_kill?(tracker, time_kill_minutes: time_kill_minutes)
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

      # Ratchet the profit floor upward as HWM PnL grows.
      # Monotonic — floor only moves up, never down.
      # Called every monitor cycle once the floor is armed.
      # @param tracker [PositionTracker]
      # @param hwm_pnl [BigDecimal, nil] High water mark PnL from Redis snapshot
      # @param trail_pct [Numeric] Floor as DECIMAL fraction of HWM (e.g., 0.70 = protect 70% of peak)
      def update_trailing_floor!(tracker, hwm_pnl, trail_pct:)
        return unless hwm_pnl&.positive?

        # trail_pct is DECIMAL (0.70), so no division by 100 needed
        dynamic_floor = (BigDecimal(hwm_pnl.to_s) * BigDecimal(trail_pct.to_s)).ceil
        current_floor = BigDecimal(tracker.profit_floor_rupees.to_s)
        return if dynamic_floor <= current_floor

        # profit_floor_rupees is stored in meta (store_accessor), not a DB column
        meta = (tracker.meta || {}).stringify_keys
        meta['profit_floor_rupees'] = dynamic_floor.to_i
        tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
        Rails.logger.info(
          "[RiskManager] Trailing floor raised for #{tracker.order_no}: " \
          "₹#{current_floor} → ₹#{dynamic_floor} (HWM: ₹#{hwm_pnl.round(2)}, trail: #{(trail_pct * 100).round}%)"
        )
      rescue StandardError => e
        Rails.logger.error("[RiskManager] update_trailing_floor! failed for #{tracker.order_no}: #{e.message}")
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

      # Calculate seconds spent below entry price
      # Tracks this in Redis cache keyed by tracker_id
      def seconds_below_entry(tracker)
        cache_key = "position:below_entry:#{tracker.id}"
        cached = Rails.cache.read(cache_key)

        snapshot = pnl_snapshot(tracker)
        return 0 unless snapshot

        pnl_pct = snapshot[:pnl_pct]
        return 0 if pnl_pct.nil? || pnl_pct >= 0

        # If position is below entry, increment counter
        Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
        if cached
          # Update timestamp if still below entry
          (Time.current - cached).to_i
        else
          # First time below entry, initialize
          0
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] seconds_below_entry error for #{tracker.id}: #{e.class} - #{e.message}")
        0
      end

      # Calculate ATR ratio (current ATR / recent ATR average)
      # Returns 1.0 if calculation fails (normal volatility)
      def calculate_atr_ratio(tracker)
        instrument = tracker.instrument || tracker.watchable&.instrument
        return 1.0 unless instrument

        # Try to get ATR from instrument's candle series
        begin
          series = instrument.candle_series(interval: '5') # 5-minute candles
          return 1.0 unless series&.candles&.any?

          candles = series.candles.last(20) # Last 20 candles
          return 1.0 if candles.size < 10

          # Calculate current ATR (last 14 periods)
          current_atr = calculate_atr(candles.last(14))
          return 1.0 unless current_atr.positive?

          # Calculate average ATR (last 20 periods)
          avg_atr = calculate_atr(candles)
          return 1.0 unless avg_atr.positive?

          ratio = current_atr / avg_atr
          ratio.round(3)
        rescue StandardError => e
          Rails.logger.debug { "[RiskManager] ATR ratio calculation failed for #{tracker.order_no}: #{e.message}" }
          1.0
        end
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

        (price_change.abs * 100 * volume_factor).round(2)
      end

      def mark_breakeven_reached!(tracker, net_pnl, threshold_rupees:)
        return if tracker.be_set?
        return unless BigDecimal(threshold_rupees.to_s) <= net_pnl

        tracker.update!(be_set: true)
      rescue StandardError => e
        Rails.logger.warn("[RiskManager] mark_breakeven_reached! failed for #{tracker.order_no}: #{e.class} - #{e.message}")
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

      def profit_floor_time_kill?(tracker, time_kill_minutes:)
        return false unless time_kill_minutes
        return false unless tracker.profit_floor_set_at

        (Time.current - tracker.profit_floor_set_at) >= time_kill_minutes.minutes
      rescue StandardError
        false
      end

      def transition_to_secured_profit_zone(tracker, net_pnl_rupees, _target_profit_rupees)
        # Check if already transitioned
        return if tracker.meta&.dig('profit_zone_state') == 'secured_profit_zone'

        # Move SL to green (+₹500 to +₹1,000)
        secured_sl_config = post_profit_zone_config
        secured_sl_rupees = BigDecimal((secured_sl_config[:secured_sl_rupees] || 800).to_s)

        # Calculate entry price and quantity
        entry_price = tracker.entry_price
        quantity = tracker.quantity
        return unless entry_price && quantity&.positive?

        # Calculate SL price that gives us secured_sl_rupees profit
        # Formula: (sl_price - entry_price) * quantity - exit_fee = secured_sl_rupees
        # sl_price = entry_price + (secured_sl_rupees + exit_fee) / quantity
        exit_fee = BrokerFeeCalculator.fee_per_order
        sl_price = entry_price + (BigDecimal((secured_sl_rupees + exit_fee).to_s) / quantity)

        # Update tracker metadata
        meta = tracker.meta || {}
        meta = {} unless meta.is_a?(Hash)
        meta['profit_zone_state'] = 'secured_profit_zone'
        meta['secured_sl_price'] = sl_price.to_f
        meta['secured_sl_rupees'] = secured_sl_rupees.to_f
        meta['profit_zone_transitioned_at'] = Time.current.iso8601

        tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations

        Rails.logger.info(
          "[RiskManager] Transitioned #{tracker.order_no} to SECURED_PROFIT_ZONE " \
          "(PnL: ₹#{net_pnl_rupees.round(2)}, SL: ₹#{secured_sl_rupees}, SL Price: ₹#{sl_price.round(2)})"
        )
      rescue StandardError => e
        Rails.logger.error("[RiskManager] transition_to_secured_profit_zone error: #{e.class} - #{e.message}")
      end

      def build_position_data_for_rule_engine(tracker, snapshot)
        # Build PositionData compatible with RuleContext
        instrument = tracker.instrument || tracker.watchable&.instrument
        index_key = tracker.meta&.dig('index_key') || instrument&.symbol_name

        Positions::ActiveCache::PositionData.new(
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
        Risk::ProfitManager.instance.peak_profit_pct_for(tracker, snapshot)
      end
    end
  end
end
