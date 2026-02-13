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

        advance_trade_states!

        # ============================================================
        # NEW 5-LAYER EXIT SYSTEM (optimized for intraday options buying)
        # ============================================================
        # Priority order: first-match-wins, evaluation stops on exit
        # This replaces the previous over-engineered system with a clean,
        # options-aligned exit mechanism.
        # ============================================================
        exit_engine = @exit_engine || self

        # LAYER 0: EXECUTABLE R STOP (Premium-based hard stop)
        enforce_premium_r_stop(exit_engine: exit_engine)

        # LAYER 1: HARD RISK CIRCUIT BREAKER (Account protection - highest priority)
        # Purpose: Account protection ONLY - no trade logic
        enforce_hard_rupee_stop_loss(exit_engine: exit_engine)

        # PROFIT FLOOR (Stateful guarantee - protect locked profits)
        # Purpose: Once net PnL reaches lock_rupees, exit if it drops back to that floor
        enforce_profit_floor(exit_engine: exit_engine)

        # LAYER 2: STRUCTURE INVALIDATION (Primary exit - structure breaks against position)
        # Purpose: Exit when trade thesis is broken - structure-first, not PnL-first
        enforce_structure_invalidation(exit_engine: exit_engine)

        # LAYER 3: PREMIUM MOMENTUM FAILURE (Kill dead option trades before theta eats them)
        # Purpose: Exit when premium stops making progress - aligns with gamma/theta behavior
        enforce_premium_momentum_failure(exit_engine: exit_engine)

        # LAYER 4: TIME STOP (Early, contextual - prevent holding dead trades)
        # Purpose: Exit regardless of PnL when time limit exceeded
        enforce_time_stop(exit_engine: exit_engine)

        # LAYER 5: END-OF-DAY FLATTEN (Operational safety - 3:20 PM exit)
        # Purpose: Operational safety - always exit before market close
        enforce_time_based_exit(exit_engine: exit_engine)

        # ============================================================
        # LEGACY RULES DISABLED (kept for reference, not called)
        # ============================================================
        # These are replaced by the new 5-layer system:
        # - enforce_early_trend_failure → replaced by premium_momentum_failure
        # - enforce_global_time_overrides → replaced by structure_invalidation + premium_momentum_failure
        # - enforce_hard_limits (rupee TP) → removed (not aligned with options)
        # - enforce_post_profit_zone → removed (not aligned with options)
        # - enforce_trailing_stops → replaced by premium_momentum_failure
        # ============================================================
      end
    end
  end
end
