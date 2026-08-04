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

      # Legacy fallback method for spec compatibility
      def enforce_trailing_stops(exit_engine:)
        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          position_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
          next unless position_data

          pnl_pct = position_data.pnl_pct.to_f

          # Breakeven Lock Logic
          risk_cfg = AlgoConfig.fetch[:risk] || {}
          breakeven_pct = (risk_cfg[:breakeven_after_gain] || 0.15).to_f
          if pnl_pct >= breakeven_pct && !tracker.breakeven_locked?
            tracker.lock_breakeven!
          end

          # Trailing stop activation threshold
          t_config = Positions::TrailingConfig.from_tracker(tracker)

          if t_config.hybrid_atr_enabled?
            ltp = position_data.current_ltp.to_f
            entry = position_data.entry_price.to_f
            peak = position_data.respond_to?(:peak_price) && position_data.peak_price.to_f.positive? ? position_data.peak_price.to_f : [ltp, entry].max
            atr_val = position_data.respond_to?(:atr) ? position_data.atr.to_f : 0.0

            hybrid_sl = if ltp.positive? && entry.positive? && atr_val.positive?
                          t_config.calculate_hybrid_atr_trailing_sl(
                            current_price: ltp,
                            entry_price: entry,
                            peak_price: peak,
                            current_profit_pct: pnl_pct,
                            atr_value: atr_val
                          )
                        end

            if hybrid_sl && ltp <= hybrid_sl
              reason = "hybrid_atr_trailing_exit (ltp: #{ltp}, sl: #{hybrid_sl})"
              dispatch_exit(exit_engine, tracker, reason)
              next
            end
          end

          activation_pct = t_config.direct_trailing_activation_profit_pct.to_f
          next if pnl_pct < activation_pct

          # Peak drawdown check using TrailingConfig
          peak_pct = position_data.peak_profit_pct.to_f
          if Positions::TrailingConfig.peak_drawdown_triggered?(peak_pct, pnl_pct)
            reason = "peak_drawdown_exit (peak: #{peak_pct}, current: #{pnl_pct})"
            dispatch_exit(exit_engine, tracker, reason)
          end
        end
      end

      # Legacy fallback method for spec compatibility
      def enforce_early_trend_failure(exit_engine:)
        nil
      end

      def enforce_premium_r_stop(exit_engine:)
        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          enforce_premium_r_stop_for(tracker, exit_engine: exit_engine)
        end
      end

      def enforce_premium_r_stop_for(tracker, exit_engine:, position_data: nil, pending_meta: nil)
        position_data ||= Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        return unless position_data

        ltp = position_data.current_ltp
        return unless ltp

        premium_stop = (pending_meta || tracker.meta || {})["premium_stop_price"]
        return unless premium_stop

        return unless ltp.to_f <= premium_stop.to_f

        reason = "PREMIUM_R_STOP (ltp: #{ltp}, stop: #{premium_stop})"
        exit_path = "premium_r_stop"
        Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
        track_exit_path(tracker, exit_path, reason)
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_premium_r_stop_for error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end

      def enforce_eod_force_close(exit_engine:, position_data: nil)
        risk = risk_config
        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || "15:30")
        return unless market_close_time

        now = Time.current
        return unless now >= market_close_time

        Positions::ActivePositionsCache.instance.active_trackers.each do |tracker|
          next if tracker.exit_requested_at.present? || tracker.exit_sent_at.present?
          next if carry_held?(tracker)

          reason = "MARKET_CLOSE (EOD #{market_close_time.strftime('%H:%M')} IST)"
          exit_path = "eod_force_close"
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_eod_force_close error: #{e.class} - #{e.message}")
      end

      def carry_held?(tracker)
        return true if trackers_profitable?(tracker) && OptionsBuying::Mode.intraday?
        return true if OptionsBuying::CarryPolicy.carry_still_valid?(tracker)

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

      # All positions use product_type NORMAL (not INTRADAY) so DhanHQ RMS never
      # auto-squares them.  At EOD we only force-close positions in loss; profitable
      # positions survive and carry to the next session.
      def trackers_profitable?(tracker)
        return false unless tracker.active?
        return false if tracker.exited?
        return false if tracker.last_pnl_pct.nil?

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
