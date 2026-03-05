# frozen_string_literal: true

module Live
  class RiskManagerService
    module ExitEnforcement
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
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          pnl_pct = snapshot[:pnl_pct]
          next if pnl_pct.nil?

          # ETF only applies before trailing activation (when profit < activation threshold)
          pnl_pct_value = pnl_pct.to_f * 100.0
          next unless Live::EarlyTrendFailure.applicable?(pnl_pct_value, activation_profit_pct: activation_profit)

          # Build position_data hash for ETF check
          instrument = tracker.instrument || tracker.watchable&.instrument
          next unless instrument

          position_data = build_position_data_for_etf(tracker, snapshot, instrument)

          if Live::EarlyTrendFailure.early_trend_failure?(position_data)
            reason = "EARLY_TREND_FAILURE (pnl: #{pnl_pct_value.round(2)}%)"
            exit_path = 'early_trend_failure'
            Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
            track_exit_path(tracker, exit_path, reason)
            dispatch_exit(exit_engine, tracker, reason)
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_early_trend_failure error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
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
          val = risk[:exit_drop_pct]
          (val.nil? || val.to_s.empty?) ? BigDecimal('999') : BigDecimal(val.to_s)
        rescue StandardError
          BigDecimal('999')
        end

        puts "[DEBUG] risk: #{risk.inspect}"
        puts "[DEBUG] drop_threshold: #{drop_threshold}"

        # Skip if trailing is disabled (threshold too high)
        return if drop_threshold >= 100

        breakeven_gain = begin
          BigDecimal(risk[:breakeven_after_gain].to_s)
        rescue StandardError
          BigDecimal(999) # Disabled by default
        end

        PositionTracker.active.find_each do |tracker|
          next unless tracker.trade_state == 'expansion'

          snap = pnl_snapshot(tracker)
          next unless snap

          pnl = snap[:pnl]
          pnl_pct = snap[:pnl_pct]
          hwm = snap[:hwm_pnl]
          next if hwm.nil? || hwm.zero?

          pnl_pct_value = pnl_pct.to_f * 100.0

          # BIDIRECTIONAL TRAILING LOGIC

        # 1. UPWARD TRAILING (when profitable)
        if pnl_pct_value.positive?
          # Calculate peak profit percentage
          peak_profit_pct = (hwm / (tracker.entry_price.to_f * tracker.quantity.to_i)) * 100.0

          # Activation threshold for adaptive drawdown
          drawdown_cfg = begin
            (AlgoConfig.fetch[:risk] && AlgoConfig.fetch[:risk][:drawdown]) || {}
          rescue StandardError
            {}
          end
          activation_profit = drawdown_cfg[:activation_profit_pct].to_f.nonzero? || 3.0

          if peak_profit_pct >= activation_profit
            # ADAPTIVE ZONE: Use adaptive drawdown schedule
            index_key = tracker.meta&.dig('index_key') || tracker.instrument&.symbol_name
            allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(peak_profit_pct, index_key: index_key)

            if allowed_dd
              allowed_drop_from_hwm = allowed_dd / peak_profit_pct
              current_drop = (hwm - pnl) / hwm

              if current_drop >= allowed_drop_from_hwm
                reason = "ADAPTIVE_TRAILING_STOP (peak: #{peak_profit_pct.round(2)}%, drop: #{(current_drop * 100).round(2)}%, allowed: #{(allowed_drop_from_hwm * 100).round(2)}%)"
                exit_path = 'trailing_stop_adaptive_upward'
                Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
                track_exit_path(tracker, exit_path, reason)
                dispatch_exit(exit_engine, tracker, reason)
                next
              end
            end

            # Breakeven locking (still applies in adaptive zone)
            if breakeven_gain < 100 && pnl_pct_value >= (breakeven_gain * 100) && !tracker.breakeven_locked?
              tracker.lock_breakeven!
              Rails.logger.info("[RiskManager] Breakeven locked for #{tracker.order_no} at #{pnl_pct_value.round(2)}% profit")
            end

            # IMPORTANT: Since we are in the adaptive zone, we SKIP fixed fallback to let adaptive take precedence
          elsif drop_threshold < 100
            # FIXED ZONE: Fallback to fixed threshold (before adaptive activation)
            drop_pct = (hwm - pnl) / hwm
            if drop_pct >= drop_threshold
              reason = "TRAILING_STOP (fixed threshold: #{(drop_threshold * 100).round(2)}%, drop: #{(drop_pct * 100).round(2)}%)"
              exit_path = 'trailing_stop_fixed_upward'
              Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
              track_exit_path(tracker, exit_path, reason)
              dispatch_exit(exit_engine, tracker, reason)
              next
            end

            # Breakeven locking (still applies in fixed zone)
            if breakeven_gain < 100 && pnl_pct_value >= (breakeven_gain * 100) && !tracker.breakeven_locked?
              tracker.lock_breakeven!
              Rails.logger.info("[RiskManager] Breakeven locked for #{tracker.order_no} at #{pnl_pct_value.round(2)}% profit")
            end
          end
        end

          # 2. DOWNWARD TRAILING (when below entry): Use reverse dynamic SL
          # This is handled in enforce_hard_limits, but we can add additional trailing logic here
          # For now, reverse SL is handled in enforce_hard_limits via dynamic reverse SL
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_trailing_stops error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
          Rails.logger.error("[RiskManager] Backtrace: #{e.backtrace.first(5).join(', ')}")
        end
      end

      def advance_trade_states!
        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          entry_risk_rupees = tracker.meta&.dig('entry_risk_rupees')
          risk_value = safe_big_decimal(entry_risk_rupees)
          next unless risk_value&.positive?

          net_pnl = safe_big_decimal(snapshot[:pnl])
          next unless net_pnl

          current_r = (net_pnl / risk_value).to_f

          if tracker.trade_state.blank?
            tracker.update_column(:trade_state, 'init')
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
          Rails.logger.error("[RiskManager] advance_trade_states error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
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

        stall_candles = stall_detection_config[:stall_candles] || 3
        min_profit_for_stall_check = BigDecimal((stall_detection_config[:min_profit_rupees] || 2000).to_s)

        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          pnl_rupees = snapshot[:pnl]
          next unless pnl_rupees && pnl_rupees >= min_profit_for_stall_check

          # Check if price has stalled (no new HH/LL for N candles)
          if price_stalled?(tracker, stall_candles)
            reason = "PRICE_STALL (#{stall_candles} candles no progress, profit: ₹#{pnl_rupees.round(2)})"
            exit_path = 'stall_detection'
            Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
            track_exit_path(tracker, exit_path, reason)
            dispatch_exit(exit_engine, tracker, reason)
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_stall_detection_exit error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end


      def enforce_time_based_exit(exit_engine:)
        risk = risk_config
        exit_time = parse_time_hhmm(risk[:time_exit_hhmm] || '15:20')
        return unless exit_time

        now = Time.current
        return unless now >= exit_time

        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return if market_close_time && now >= market_close_time

        PositionTracker.active.find_each do |tracker|
          tracker.hydrate_pnl_from_cache!
          if tracker.last_pnl_rupees.present? && tracker.last_pnl_rupees.positive?
            min_profit = begin
              BigDecimal((risk[:min_profit_rupees] || 0).to_s)
            rescue StandardError
              BigDecimal(0)
            end
            if min_profit.positive? && tracker.last_pnl_rupees < min_profit
              Rails.logger.info("[RiskManager] Time-based exit skipped for #{tracker.order_no} - PnL < min_profit")
              next
            end
          end

          reason = "time-based exit (#{exit_time.strftime('%H:%M')})"
          exit_path = 'time_based'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_time_based_exit error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      # ============================================================
      # NEW 5-LAYER EXIT SYSTEM ENFORCEMENT METHODS
      # ============================================================

      # LAYER 1: HARD RISK CIRCUIT BREAKER
      # Purpose: Account protection ONLY - no trade logic

      # HARD RUPEE TAKE PROFIT
      # Purpose: Exit immediately when net PnL reaches the target rupee amount.
      # Mirrors enforce_hard_rupee_stop_loss — same pattern, opposite direction.

      # LAYER 0: EXECUTABLE R STOP (premium hard stop)
      # Purpose: Enforce 1R loss cap in premium terms, independent of structure recalculation.
      def enforce_premium_r_stop(exit_engine:)
        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          ltp = snapshot[:ltp]
          next unless ltp

          premium_stop = tracker.meta&.dig('premium_stop_price')
          next unless premium_stop

          if ltp.to_f <= premium_stop.to_f
            reason = "PREMIUM_R_STOP (ltp: #{ltp}, stop: #{premium_stop})"
            exit_path = 'premium_r_stop'
            Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
            track_exit_path(tracker, exit_path, reason)
            dispatch_exit(exit_engine, tracker, reason)
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_premium_r_stop error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      # LAYER 1: DYNAMIC TRAILING SL
      # Purpose: Move SL up-only to capture trend moves (direct trailing)
      def enforce_dynamic_trailing_stops(exit_engine:)
        engine = @trailing_engine ||= Live::TrailingEngine.new()

        PositionTracker.active.find_each do |tracker|
          # TrailingEngine expects PositionData from ActiveCache
          position_data = @active_cache.get_position(tracker.id)
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

        exited = false
        PositionTracker.active.find_each do |tracker|
          break if exited

          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          # Build rule context
          position_data = build_position_data_for_rule_engine(tracker, snapshot)
          context = Risk::Rules::RuleContext.new(
            position: position_data,
            tracker: tracker,
            risk_config: risk_config
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
            exited = true # Exit immediately on first match
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_structure_invalidation error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      # LAYER 3: PREMIUM MOMENTUM FAILURE
      # Purpose: Kill dead option trades before theta eats them
      def enforce_premium_momentum_failure(exit_engine:)
        return unless premium_momentum_failure_enabled?

        exited = false
        PositionTracker.active.find_each do |tracker|
          break if exited

          snapshot = pnl_snapshot(tracker)
          next unless snapshot

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
            exited = true # Exit immediately on first match
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_premium_momentum_failure error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      # LAYER 4: TIME STOP
      # Purpose: Prevent holding dead trades - exit regardless of PnL when time limit exceeded
      def enforce_time_stop(exit_engine:)
        return unless time_stop_enabled?

        exited = false
        PositionTracker.active.find_each do |tracker|
          break if exited

          snapshot = pnl_snapshot(tracker)
          next unless snapshot

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
            exited = true # Exit immediately on first match
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_time_stop error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      # LAYER 5: RR-BASED PROFIT BOOKING
      # Purpose: Capture profits at pre-defined R multiples (e.g., 2R, 3R)
      def enforce_rr_profit_booking(exit_engine:)
        return unless rr_profit_booking_enabled?

        cfg = rr_profit_booking_config
        target_rr = (cfg[:target_rr] || 2.0).to_f

        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          pnl_pct = snapshot[:pnl_pct]
          next if pnl_pct.nil?

          # Get initial risk (SL) from tracker meta or default
          sl_pct = tracker.meta&.dig('initial_sl_pct')&.to_f

          # Fallback: if premium_stop_price exists, calculate sl_pct from it
          if sl_pct.nil? || sl_pct.zero?
            premium_stop = tracker.meta&.dig('premium_stop_price')&.to_f
            if premium_stop && premium_stop.positive?
              entry = tracker.entry_price.to_f
              sl_pct = ((entry - premium_stop) / entry).abs * 100.0
            end
          end

          # Second fallback: use global default SL pct
          sl_pct ||= pct_value(risk_config[:sl_pct] || 10).to_f

          next if sl_pct.zero?

          # RR = Profit% / SL%
          current_rr = (pnl_pct.to_f * 100.0) / sl_pct

          if current_rr >= target_rr
            reason = "RR_PROFIT_BOOKING (RR: #{current_rr.round(2)}, Target: #{target_rr}, PnL: #{(pnl_pct.to_f * 100).round(2)}%, SL: #{sl_pct.round(2)}%)"
            exit_path = 'rr_profit_booking'
            Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
            track_exit_path(tracker, exit_path, reason)
            dispatch_exit(exit_engine, tracker, reason)
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_rr_profit_booking error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      # LAYER 4.5: PERCENTAGE-BASED PNL EXIT
      # Purpose: Full exit when target % PnL is reached (independent of initial risk)
      def enforce_percentage_pnl_exit(exit_engine:)
        cfg = (risk_config[:percentage_pnl_exit] || {})
        return unless cfg[:enabled]

        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

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
          Rails.logger.error("[RiskManager] enforce_percentage_pnl_exit error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      # Profit-Floor enforcement (stateful guarantee).
      #
      # Guarantee (best-effort, subject to tick granularity + slippage):
      # - Once net PnL reaches lock_rupees, we arm a floor.
      # - If net PnL drops to floor + exit_fee, we immediately exit.
      #
      # This lives in the decision plane (RiskManagerService), not ExitEngine.
      def enforce_profit_floor(exit_engine:)
        cfg = profit_floor_config
        return unless cfg[:enabled]

        lock_pct = cfg[:lock_pct]
        lock_rupees_static = cfg[:lock_rupees]  # fallback if lock_pct not set
        breakeven_at = cfg[:breakeven_at]
        time_kill_minutes = cfg[:time_kill_minutes]
        exit_fee = BrokerFeeCalculator.fee_per_order

        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          net_pnl = safe_big_decimal(snapshot[:pnl])
          next unless net_pnl

          # Compute lock threshold: prefer lock_pct% of capital_deployed (position-size aware),
          # fall back to static lock_rupees if lock_pct not configured.
          lock_rupees = if lock_pct
                          capital = safe_big_decimal(snapshot[:capital_deployed])
                          capital&.positive? ? (capital * BigDecimal(lock_pct.to_s) / 100).ceil : lock_rupees_static
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
          next unless floor

          if profit_floor_time_kill?(tracker, time_kill_minutes: time_kill_minutes)
            reason = "PROFIT_FLOOR_TIME_KILL (floor: ₹#{floor}, age_min: #{time_kill_minutes})"
            exit_path = 'profit_floor_time_kill'
            Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
            track_exit_path(tracker, exit_path, reason)
            dispatch_exit(exit_engine, tracker, reason)
            next
          end

          threshold = BigDecimal(floor.to_s) + BigDecimal(exit_fee.to_s)
          next unless net_pnl <= threshold

          final_net_pnl = net_pnl - BigDecimal(exit_fee.to_s)
          reason = "PROFIT_FLOOR_LOCK (Current net: ₹#{net_pnl.round(2)}, Net after exit: ₹#{final_net_pnl.round(2)}, floor: ₹#{floor})"
          exit_path = 'profit_floor_lock'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] enforce_profit_floor error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        end
      end

      private

      # Ratchet the profit floor upward as HWM PnL grows.
      # Monotonic — floor only moves up, never down.
      # Called every monitor cycle once the floor is armed.
      # @param tracker [PositionTracker]
      # @param hwm_pnl [BigDecimal, nil] High water mark PnL from Redis snapshot
      # @param trail_pct [Numeric] Floor as % of HWM (e.g., 70 = protect 70% of peak)
      def update_trailing_floor!(tracker, hwm_pnl, trail_pct:)
        return unless hwm_pnl&.positive?

        dynamic_floor = (BigDecimal(hwm_pnl.to_s) * BigDecimal(trail_pct.to_s) / 100).ceil
        current_floor = BigDecimal(tracker.profit_floor_rupees.to_s)
        return if dynamic_floor <= current_floor

        tracker.update_column(:profit_floor_rupees, dynamic_floor.to_i)
        Rails.logger.info(
          "[RiskManager] Trailing floor raised for #{tracker.order_no}: " \
          "₹#{current_floor} → ₹#{dynamic_floor} (HWM: ₹#{hwm_pnl.round(2)}, trail: #{trail_pct}%)"
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

      # Build position data hash for Early Trend Failure checks
      def build_position_data_for_etf(tracker, _snapshot, instrument)
        # Get trend metrics from instrument
        series = begin
          instrument.candle_series(interval: '5')
        rescue StandardError
          nil
        end
        candles = series&.candles || []

        # Calculate ADX
        adx_value = begin
          instrument.adx(14, interval: '5')
        rescue StandardError
          nil
        end
        adx_hash = adx_value.is_a?(Hash) ? adx_value : { value: adx_value }

        # Calculate ATR ratio
        atr_ratio = calculate_atr_ratio(tracker)

        # Get underlying price (for VWAP check)
        underlying_price = current_ltp(tracker) || tracker.entry_price.to_f

        # Build trend score (simplified: use ADX + momentum)
        trend_score = if adx_hash[:value]
                        adx_hash[:value].to_f + (candles.any? ? momentum_score(candles) : 0)
                      else
                        0
                      end

        # Peak trend score (tracked in Redis or use current if no peak)
        peak_trend_score = tracker.meta&.dig('peak_trend_score') || trend_score
        if trend_score > peak_trend_score
          peak_trend_score = trend_score
          tracker.update(meta: (tracker.meta || {}).merge('peak_trend_score' => peak_trend_score))
        end

        # VWAP (simplified: use recent average price)
        vwap = candles.any? ? candles.last(20).sum(&:close) / candles.last(20).size : underlying_price

        OpenStruct.new(
          trend_score: trend_score,
          peak_trend_score: peak_trend_score,
          adx: adx_hash[:value],
          atr_ratio: atr_ratio,
          underlying_price: underlying_price,
          vwap: vwap,
          is_long?: %w[long_ce long_pe].include?(tracker.side)
        )
      rescue StandardError => e
        Rails.logger.error("[RiskManager] build_position_data_for_etf error: #{e.class} - #{e.message}")
        OpenStruct.new(
          trend_score: 0,
          peak_trend_score: 0,
          adx: nil,
          atr_ratio: 1.0,
          underlying_price: tracker.entry_price.to_f,
          vwap: tracker.entry_price.to_f,
          is_long?: true
        )
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

        tracker.update_column(:meta, meta)

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
        hwm = snapshot[:hwm_pnl]
        return nil unless hwm&.positive?

        entry_price = tracker.entry_price
        quantity = tracker.quantity
        return nil unless entry_price && quantity&.positive?

        buy_value = entry_price * quantity
        return nil unless buy_value.positive?

        (hwm / buy_value).to_f
      end
    end
  end
end
