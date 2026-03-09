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

        # ============================================================
        # 5-LAYER EXIT SYSTEM (Template Method: run_enforcement_cycle)
        # Priority order: first-match-wins, evaluation stops on exit
        # ============================================================
        exit_engine = @exit_engine || self
        run_enforcement_cycle(exit_engine)
      end

      # Template method: single algorithm skeleton for all exit enforcement layers.
      # Add or reorder enforcement by editing this method.
      def run_enforcement_cycle(exit_engine)
        PositionTracker.active.find_each do |tracker|
          # Skip if position is already being exited (prevents race conditions with high-frequency triggers)
          next if tracker.exit_requested_at.present? || tracker.exit_sent_at.present?

          # Advance trade state before evaluating rules (updates trade_state, peak_trend_score etc)
          advance_trade_state_for(tracker)

          enforce_hard_limits_for(tracker, exit_engine: exit_engine)
          enforce_early_trend_failure_for(tracker, exit_engine: exit_engine)
          enforce_premium_r_stop_for(tracker, exit_engine: exit_engine)
          enforce_dynamic_trailing_stops_for(tracker, exit_engine: exit_engine)
          enforce_profit_floor_for(tracker, exit_engine: exit_engine)
          enforce_structure_invalidation_for(tracker, exit_engine: exit_engine)
          enforce_premium_momentum_failure_for(tracker, exit_engine: exit_engine)
          enforce_rr_profit_booking_for(tracker, exit_engine: exit_engine)
          enforce_percentage_pnl_exit_for(tracker, exit_engine: exit_engine)
          enforce_time_stop_for(tracker, exit_engine: exit_engine)
          enforce_time_based_exit_for(tracker, exit_engine: exit_engine)
        end
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
    end
  end
end
