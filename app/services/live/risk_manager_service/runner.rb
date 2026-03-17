# frozen_string_literal: true

module Live
  class RiskManagerService
    module Runner
      private

      # Start watchdog thread to ensure service thread is restarted if it dies
      def start_watchdog
        @watchdog_thread = Thread.new do
          Thread.current.name = 'risk-manager-watchdog'
          loop do
            break unless @running # Exit if service is stopped

            unless @thread&.alive?
              Rails.logger.warn('[RiskManagerService] Watchdog detected dead thread — restarting...')
              # Reset running flag if thread is dead or nil
              @running = false
              start
            end
            sleep 10
          end
        end
      end

      # Central monitoring loop: keep PnL and caches fresh.
      # Always run enforcement - ExitEngine is only used for executing exits, not for triggering them.
      def monitor_loop(last_paper_pnl_update)
        # Clear per-cycle caches at the start
        @redis_pnl_cache = {}
        @cycle_tracker_map = nil

        # Skip processing if market is closed and no active positions
        if TradingSession::Service.market_closed?
          # Only fetch once after market closes, then skip all checks until market opens
          if @market_closed_checked
            # Already checked after market closed - if we're here, positions exist
            # Continue monitoring for exits (positions were found in first check)
          else
            # First check after market closed - fetch once to verify no positions
            active_count = Positions::ActivePositionsCache.instance.active_trackers.size
            @market_closed_checked = true

            if active_count.zero?
              # Market closed and no active positions - no need to monitor
              # Mark as checked and return early - won't check again until market opens
              Rails.logger.debug('[RiskManager] Market closed with no positions - skipping monitoring until market opens')
              return
            end
            # Market closed but positions exist - continue monitoring (needed for exits)
          end
        else
          # Market is open - reset the flag so we check again next time market closes
          @market_closed_checked = false
        end

        # Keep Redis/DB PnL fresh (only if market open or positions exist)
        update_paper_positions_pnl_if_due(last_paper_pnl_update)
        ensure_all_positions_in_redis

        # Skip enforcement methods if market closed and no positions (avoid DB queries)
        return if skip_enforcement_due_to_market_closed?

        # Circuit breaker — force-close all positions if tripped, then stop enforcement
        if Risk::CircuitBreaker.instance.tripped?
          cb = Risk::CircuitBreaker.instance.status
          Rails.logger.error("[RiskManager] Circuit breaker active (#{cb[:reason]}) — force-closing all positions")
          Risk::CircuitBreaker.instance.force_close_all!(exit_engine: exit_engine, reason: "circuit_breaker: #{cb[:reason]}")
          return
        end

        exit_engine = @exit_engine || self
        run_interval_enforcement_if_needed(exit_engine)
      end

      # Interval fallback enforcement when realtime tick-first path is stale/unavailable.
      # EOD force-close runs every loop when at/past market close so it is never skipped by tick-first.
      # When outside trading window (pre 9:20 or post 15:30): run EOD only in 15:30–16:00; skip all enforcement otherwise.
      def run_interval_enforcement_if_needed(exit_engine)
        if outside_trading_window?
          return unless in_eod_force_close_window?
          enforce_eod_force_close(exit_engine: exit_engine)
          return
        end

        risk = risk_config
        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        if market_close_time && Time.current >= market_close_time
          enforce_eod_force_close(exit_engine: exit_engine)
          return
        end

        return run_enforcement_cycle(exit_engine) unless realtime_tick_first_enabled?

        if tick_stream_fresh?
          Rails.logger.debug('[RiskManager] Tick-first mode active; skipping interval exit scan') if should_log_realtime_skip?
          return
        end

        unless realtime_fallback_enabled?
          Rails.logger.warn('[RiskManager] Tick stream stale and fallback disabled; skipping interval exit scan')
          return
        end

        Rails.logger.warn('[RiskManager] Tick stream stale; running interval fallback exit scan')
        run_enforcement_cycle(exit_engine)
      end

      # Template method: single algorithm skeleton for all exit enforcement layers.
      # Add or reorder enforcement by editing this method.
      # First-match-wins: after any layer triggers an exit, we skip remaining layers for that tracker.
      # EOD force-close runs first when at or past market close so intraday positions never carry overnight.
      def run_enforcement_cycle(exit_engine)
        enforce_eod_force_close(exit_engine: exit_engine)

        risk = risk_config
        market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
        return if market_close_time && Time.current >= market_close_time

        PositionTracker.active.find_each do |tracker|
          run_enforcement_for_tracker(tracker, exit_engine)
        end
      end

      def run_enforcement_for_tracker(tracker, exit_engine)
        return if tracker.exit_requested_at.present? || tracker.exit_sent_at.present?

        # Advance trade state before evaluating rules (updates trade_state, peak_trend_score etc)
        advance_trade_state_for(tracker)

        enforce_premium_r_stop_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_dynamic_trailing_stops_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_profit_floor_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_structure_invalidation_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_premium_momentum_failure_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_rr_profit_booking_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_percentage_pnl_exit_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_time_stop_for(tracker, exit_engine: exit_engine)
        return if exit_requested_or_sent?(tracker)

        enforce_time_based_exit_for(tracker, exit_engine: exit_engine)
      end

      def tick_stream_fresh?
        last = @last_realtime_tick_at
        return false unless last

        (Time.current - last) <= realtime_tick_stale_after_seconds
      end

      def should_log_realtime_skip?
        @last_realtime_skip_log_at ||= Time.zone.at(0)
        return false if Time.current - @last_realtime_skip_log_at < 30.seconds

        @last_realtime_skip_log_at = Time.current
        true
      end

      def exit_requested_or_sent?(tracker)
        tracker.reload
        tracker.exit_requested_at.present? || tracker.exit_sent_at.present?
      end

      def exits_blocked_by_time?
        restrictions = AlgoConfig.fetch[:trading_time_restrictions]
        return false unless restrictions&.[](:enabled) && restrictions[:block_exits]
        return false if restrictions[:avoid_periods].blank?

        current_hm = Time.zone.now.strftime('%H:%M')
        restrictions[:avoid_periods].any? do |period|
          start_time, end_time = period.split('-')
          current_hm >= start_time && current_hm < end_time
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] exits_blocked_by_time? error: #{e.message}")
        false
      end

      # True when outside continuous trading window (before 9:20 or after 15:30 IST).
      def outside_trading_window?
        TradingSession::Service.market_closed?
      end

      # True only in 15:30–16:00 IST so EOD force-close runs once after close, not at 1 AM or weekend.
      def in_eod_force_close_window?
        return false unless TradingSession::Service.after_market_close_time?

        ist = TradingSession::Service.current_ist_time
        now_min = (ist.hour * 60) + ist.min
        close_min = (TradingSession::Service::MARKET_CLOSE_HOUR * 60) + TradingSession::Service::MARKET_CLOSE_MINUTE
        end_min = (16 * 60) + 0
        now_min >= close_min && now_min < end_min
      end
    end
  end
end
