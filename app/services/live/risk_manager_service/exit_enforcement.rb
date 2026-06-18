# frozen_string_literal: true

module Live
  class RiskManagerService
    module ExitEnforcement
      include Live::UnderlyingLtpResolver
      include Live::StructureInvalidationEvaluator

      # True once an exit has been requested/sent or finalized for this tracker.
      # Guards blind meta read-modify-write paths (update_column/update_columns) from
      # clobbering the authoritative meta (incl. exit_reason) that Positions::ExitFlow
      # writes atomically under lock when the position exits mid-cycle.
      def exit_in_flight?(tracker)
        tracker.exit_requested_at.present? || tracker.exit_sent_at.present? || tracker.exited?
      end

      # LAYER 1: DYNAMIC TRAILING SL
      # Purpose: Move SL up-only to capture trend moves (direct trailing)
      def enforce_dynamic_trailing_stops(exit_engine:)
        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_dynamic_trailing_stops_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_dynamic_trailing_stops_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        # TrailingEngine handles its own checks but we can filter here for efficiency
        return unless tracker.trade_state == 'expansion' || tracker.be_set?

        # Use high-performance position snapshot
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        # process_tick handles peak updates and SL adjustments
        result = (@trailing_engine ||= Live::TrailingEngine.new).process_tick(position_data, exit_engine: exit_engine, tracker: tracker, pending_meta: pending_meta)

        if result[:exit_triggered]
          Rails.logger.info("[RiskManager] TrailingEngine triggered exit for #{tracker.order_no}: #{result[:reason]}")
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_dynamic_trailing_stops_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      # LAYER 2: STRUCTURE INVALIDATION
      # Purpose: Exit when trade thesis is broken by market structure failure
      def enforce_structure_invalidation(exit_engine:)
        return unless structure_invalidation_enabled?

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_structure_invalidation_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_structure_invalidation_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        si_cfg = (risk_config[:exits] || {})[:structure_invalidation] || {}

        if si_cfg[:underlying_move_pct] && si_cfg[:premium_drop_pct]
          return unless options_structure_invalidated_enforcement?(tracker, position_data, si_cfg)

          reason = 'STRUCTURE_INVALIDATION (dual: underlying move + premium drop)'
          exit_path = 'structure_invalidation'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
          return
        end

        # Legacy rule-engine path
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

      def options_structure_invalidated_enforcement?(tracker, position_data, si_cfg)
        min_hold = (si_cfg[:min_hold_seconds] || 120).to_i
        return false unless tracker.created_at && (Time.current - tracker.created_at) >= min_hold

        index_key = tracker.meta&.dig('index_key')
        underlying_ltp = resolve_underlying_ltp(index_key)
        return false unless underlying_ltp

        dual_condition_met?(tracker, underlying_ltp, position_data.current_ltp.to_f, si_cfg)
      end

      # LAYER 3: PREMIUM MOMENTUM FAILURE
      # Purpose: Kill dead option trades before theta eats them
      def enforce_premium_momentum_failure(exit_engine:)
        return unless premium_momentum_failure_enabled?

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_premium_momentum_failure_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_premium_momentum_failure_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        # Build rule context
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

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_time_stop_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_time_stop_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        # Build rule context
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

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_rr_profit_booking_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_rr_profit_booking_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        cfg = rr_profit_booking_config
        target_rr = (cfg[:target_rr] || 2.0).to_f

        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        pnl_pct = position_data.pnl_pct
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
        sl_pct ||= (pct_value(risk_config[:sl_pct] || 0.10).to_f * 100.0)

        return if sl_pct.zero?

        # RR = Profit% / SL%
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

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_percentage_pnl_exit_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_percentage_pnl_exit_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        # Build rule context
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

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_profit_floor_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_profit_floor_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        cfg = profit_floor_config
        return unless cfg[:enabled]

        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        net_pnl = safe_big_decimal(position_data.pnl)
        return unless net_pnl

        lock_pct = cfg[:lock_pct]
        lock_rupees_static = cfg[:lock_rupees]
        breakeven_at = cfg[:breakeven_at]
        time_kill_minutes = cfg[:time_kill_minutes]
        exit_fee = BrokerFeeCalculator.fee_per_order

        # Compute lock threshold
        lock_rupees = if lock_pct
                        capital = safe_big_decimal(position_data.capital_deployed)
                        capital&.positive? ? (capital * BigDecimal(lock_pct.to_s)).ceil : lock_rupees_static
                      else
                        lock_rupees_static
                      end

        mark_breakeven_reached!(tracker, net_pnl, threshold_rupees: breakeven_at) if breakeven_at
        arm_profit_floor!(tracker, net_pnl, lock_rupees: lock_rupees) if lock_rupees
 
        # Ratchet the floor upward as HWM PnL grows (trailing floor).
        trail_pct = cfg[:trail_pct]
        if trail_pct && (pending_meta || tracker.meta || {})['profit_floor_rupees'].present?
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

      def trailing_armed_for?(tracker, position_data)
        trailing_cfg = Positions::ExitConfigResolver.for(tracker).dig(:risk, :trailing) || {}
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

      # True only in 15:30–16:00 IST so EOD force-close runs once after close.
      def enforce_eod_force_close(exit_engine:, position_data: nil)
        risk = risk_config
        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return unless market_close_time

        now = Time.current
        return unless now >= market_close_time

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          next if tracker.exit_requested_at.present? || tracker.exit_sent_at.present?
          next if carry_held?(tracker)

          reason = "MARKET_CLOSE (EOD #{market_close_time.strftime('%H:%M')} IST)"
          exit_path = 'eod_force_close'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_eod_force_close error: #{e.class} - #{e.message}")
      end

      # Skip EOD square-off for positional carries that are still valid to hold
      # (tagged by OptionsBuying::EodCarryManager when ROI clears the threshold and
      # carry is allowed for the index). Fails safe: any error → close as normal.
      def carry_held?(tracker)
        OptionsBuying::CarryPolicy.carry_still_valid?(tracker)
      rescue StandardError
        false
      end

      def enforce_time_based_exit(exit_engine:, position_data: nil)
        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_time_based_exit_for(tracker, exit_engine: exit_engine, position_data: position_data)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_time_based_exit error: #{e.class} - #{e.message}")
      end

      def enforce_time_based_exit_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        risk = risk_config
        exit_time = parse_time_hhmm(risk[:time_exit_hhmm] || '15:20')
        return unless exit_time

        now = Time.current
        return unless now >= exit_time

        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return if market_close_time && now >= market_close_time

        # Use passed position_data or fetch from cache if not provided
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        
        # We can use PnL from position_data instead of hydration
        pnl_rupees = position_data ? position_data.pnl : tracker.current_pnl_rupees.to_f

        if pnl_rupees.present? && pnl_rupees.positive?
          min_profit = begin
            BigDecimal((risk[:min_profit_rupees] || 0).to_s)
          rescue StandardError
            BigDecimal(0)
          end
          if min_profit.positive? && pnl_rupees < min_profit
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

      def update_peak_trend_score(tracker, position_data, pending_meta: nil)
        # Use trend score from position_data if available (from ActiveCache)
        trend_score = position_data.respond_to?(:underlying_trend_score) ? position_data.underlying_trend_score : nil
        
        # Fallback to calculation only if not in position_data
        if trend_score.nil?
          instrument = tracker.instrument || tracker.watchable&.instrument
          return unless instrument

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
        end

        peak = (pending_meta || tracker.meta || {})['peak_trend_score'] || 0
        if trend_score > peak
          if pending_meta
            pending_meta['peak_trend_score'] = trend_score
          elsif !exit_in_flight?(tracker)
            meta = tracker.meta || {}
            meta['peak_trend_score'] = trend_score
            tracker.update_column(:meta, meta) # rubocop:disable Rails/SkipsModelValidations
          end
        end
      rescue StandardError
        nil
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

      def profit_floor_time_kill?(tracker, time_kill_minutes:, pending_meta: nil)
        return false unless time_kill_minutes
        
        floor_set_at = (pending_meta || tracker.meta || {})['profit_floor_set_at'] || tracker.profit_floor_set_at
        return false unless floor_set_at
 
        (Time.current - floor_set_at) >= time_kill_minutes.minutes
      rescue StandardError
        false
      end

      def update_trailing_floor!(tracker, hwm_pnl, trail_pct:, pending_meta: nil)
        return unless hwm_pnl&.positive?

        dynamic_floor = (BigDecimal(hwm_pnl.to_s) * BigDecimal(trail_pct.to_s)).ceil
        current_floor = BigDecimal(tracker.profit_floor_rupees.to_s)
        return if dynamic_floor <= current_floor

        if pending_meta
          pending_meta['profit_floor_rupees'] = dynamic_floor.to_i
        elsif !exit_in_flight?(tracker)
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

      def momentum_score(candles)
        return 0 if candles.size < 3
        recent = candles.last(3)
        return 0 if recent.size < 2
        price_change = (recent.last.close - recent.first.close) / recent.first.close
        volume_factor = if recent.last.respond_to?(:volume) && recent.last.volume
                          [recent.last.volume / 1_000_000.0, 1.0].min
                        else
                          0.5
                        end
        (price_change.abs * 100 * volume_factor).round(2)
      end
    end
  end
end
