# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'
require 'ostruct'
require_relative '../concerns/broker_fee_calculator'

module Live
  # Responsible for monitoring active PositionTracker entries, keeping PnL up-to-date in Redis,
  # and enforcing exits according to configured risk rules.
  #
  # Behaviour:
  # - If an external ExitEngine is provided (recommended), RiskManagerService will NOT place exits itself.
  #   Instead ExitEngine calls the enforcement methods and RiskManagerService supplies helper functions.
  # - If no external ExitEngine is provided, RiskManagerService will execute exits itself (backwards compatibility).
  class RiskManagerService
    LOOP_INTERVAL = 5
    API_CALL_STAGGER_SECONDS = 1.0

    def initialize(exit_engine: nil)
      @exit_engine = exit_engine
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @market_closed_checked = false # Track if we've already checked after market closed

      # Watchdog ensures service thread is restarted if it dies (lightweight)
      @watchdog_thread = Thread.new do
        loop do
          unless @thread&.alive?
            Rails.logger.warn('[RiskManagerService] Watchdog detected dead thread — restarting...')
            start
          end
          sleep 10
        end
      end
    end

    # Start monitoring loop (non-blocking)
    def start
      return if @running

      @running = true

      @thread = Thread.new do
        Thread.current.name = 'risk-manager'
        last_paper_pnl_update = Time.current

        loop do
          break unless @running

          begin
            monitor_loop(last_paper_pnl_update)
            # update timestamp after paper update occurred inside monitor_loop
            last_paper_pnl_update = Time.current
          rescue StandardError => e
            Rails.logger.error("[RiskManagerService] monitor_loop crashed: #{e.class} - #{e.message}\n#{e.backtrace.first(8).join("\n")}")
          end
          sleep LOOP_INTERVAL
        end
      end
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
    end

    def running?
      @running
    end

    # Lightweight risk evaluation helper (unchanged semantics)
    def evaluate_signal_risk(signal_data)
      confidence = signal_data[:confidence] || 0.0
      entry_price = signal_data[:entry_price]
      stop_loss = signal_data[:stop_loss]

      risk_level =
        case confidence
        when 0.8..1.0 then :low
        when 0.6...0.8 then :medium
        else :high
        end

      max_position_size =
        case risk_level
        when :low then 100
        when :medium then 50
        else 25
        end

      recommended_stop_loss = stop_loss || (entry_price * 0.98)

      { risk_level: risk_level, max_position_size: max_position_size, recommended_stop_loss: recommended_stop_loss }
    end

    private

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

      # Keep Redis/DB PnL fresh
      update_paper_positions_pnl_if_due(last_paper_pnl_update)
      ensure_all_positions_in_redis

      # Always run enforcement methods - ExitEngine is only for executing exits, not triggering them
      # Use external ExitEngine if provided, otherwise use self (backwards compatibility)
      exit_engine = @exit_engine || self

      # Early Trend Failure checks (before other enforcement)
      enforce_early_trend_failure(exit_engine: exit_engine)
      enforce_global_time_overrides(exit_engine: exit_engine)
      enforce_hard_limits(exit_engine: exit_engine)
      enforce_post_profit_zone(exit_engine: exit_engine)
      enforce_trailing_stops(exit_engine: exit_engine)
      enforce_time_based_exit(exit_engine: exit_engine)
    end

    # Called by external ExitEngine or internally (when used standalone).
    # Exits triggered by enforcement logic call this method on the supplied exit_engine.
    # This method implements legacy behaviour for self-managed exits.
    def execute_exit(tracker, reason)
      # This method implements the fallback exit path when RiskManagerService is self-executing.
      # Prefer using external ExitEngine with Orders::OrderRouter for real deployments.
      Rails.logger.info("[RiskManager] execute_exit invoked for #{tracker.order_no} reason=#{reason}")

      begin
        store_exit_reason(tracker, reason)
        exit_result = exit_position(nil, tracker)
        exit_successful = exit_result.is_a?(Hash) ? exit_result[:success] : exit_result
        exit_price = exit_result.is_a?(Hash) ? exit_result[:exit_price] : nil

        if exit_successful
          tracker.mark_exited!(exit_price: exit_price, exit_reason: reason)

          # Reload tracker to get final PnL values after mark_exited!
          tracker.reload

          # Update exit reason with final PnL percentage for consistency
          # Calculate PnL percentage from final PnL value (includes broker fees)
          # This matches what Telegram notifier will display
          final_pnl = tracker.last_pnl_rupees
          entry_price = tracker.entry_price
          quantity = tracker.quantity

          if final_pnl.present? && entry_price.present? && quantity.present? &&
             entry_price.to_f.positive? && quantity.to_i.positive? && reason.present? && reason.include?('%')
            # Calculate PnL percentage (includes fees) - matches Telegram display
            pnl_pct_display = ((final_pnl.to_f / (entry_price.to_f * quantity.to_i)) * 100.0).round(2)
            # Extract the base reason (e.g., "SL HIT" or "TP HIT") - everything before the percentage
            base_reason = reason.split(/\s+-?\d+\.?\d*%/).first&.strip || reason.split('%').first&.strip || reason
            updated_reason = "#{base_reason} #{pnl_pct_display}%"

            # Always update to ensure consistency (even if values are close)
            if reason != updated_reason
              Rails.logger.info("[RiskManager] Updating exit reason for #{tracker.order_no}: '#{reason}' -> '#{updated_reason}' (PnL: ₹#{final_pnl}, PnL%: #{pnl_pct_display}%)")
              # exit_reason is a store_accessor on meta, so update via meta hash
              meta = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}
              meta['exit_reason'] = updated_reason
              tracker.update_column(:meta, meta)
            end
          else
            Rails.logger.warn("[RiskManager] Cannot update exit reason for #{tracker.order_no}: final_pnl=#{final_pnl.inspect}, entry_price=#{entry_price.inspect}, quantity=#{quantity.inspect}, reason=#{reason.inspect}")
          end

          Rails.logger.info("[RiskManager] Successfully exited #{tracker.order_no} (#{tracker.id}) via internal executor")

          # Record trade result in EdgeFailureDetector (for edge failure detection)
          record_trade_result_for_edge_detector(tracker, final_pnl, final_reason || reason)

          # Send Telegram notification
          final_reason = updated_reason || reason
          notify_telegram_exit(tracker, final_reason, exit_price)

          true
        else
          Rails.logger.error("[RiskManager] Failed to exit #{tracker.order_no} via internal executor")
          false
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] execute_exit failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        false
      end
    end

    # Enforcement methods always accept an exit_engine keyword. They do not fetch positions from caller.
    # If exit_engine is provided, they will delegate the actual exit to it. Otherwise they call internal execute_exit.
    public

    def enforce_early_trend_failure(exit_engine:)
      etf_cfg = begin
        (AlgoConfig.fetch[:risk] && AlgoConfig.fetch[:risk][:etf]) || {}
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
        Rails.logger.debug("[RiskManager] Trailing disabled for regime: #{regime}")
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

      breakeven_gain = begin
        BigDecimal(risk[:breakeven_after_gain].to_s)
      rescue StandardError
        BigDecimal(999) # Disabled by default
      end

      PositionTracker.active.find_each do |tracker|
        snap = pnl_snapshot(tracker)
        next unless snap

        pnl = snap[:pnl]
        pnl_pct = snap[:pnl_pct]
        hwm = snap[:hwm_pnl]
        next if hwm.nil? || hwm.zero?

        pnl_pct_value = pnl_pct.to_f * 100.0

        # BIDIRECTIONAL TRAILING LOGIC

        # 1. UPWARD TRAILING (when profitable): Use adaptive drawdown schedule
        if pnl_pct_value > 0
          # Calculate peak profit percentage
          peak_profit_pct = (hwm / (tracker.entry_price.to_f * tracker.quantity.to_i)) * 100.0

          # Only apply trailing if we've reached activation threshold
          drawdown_cfg = begin
            (AlgoConfig.fetch[:risk] && AlgoConfig.fetch[:risk][:drawdown]) || {}
          rescue StandardError
            {}
          end

          activation_profit = drawdown_cfg[:activation_profit_pct].to_f.nonzero? || 3.0

          if peak_profit_pct >= activation_profit
            # Use adaptive drawdown schedule instead of fixed threshold
            index_key = tracker.meta&.dig('index_key') || tracker.instrument&.symbol_name
            allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(peak_profit_pct, index_key: index_key)

            if allowed_dd
              # Convert to drop percentage from HWM
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
          end

          # Breakeven locking: Lock in breakeven when profit reaches threshold
          if breakeven_gain < 100 && pnl_pct_value >= (breakeven_gain * 100) && !tracker.breakeven_locked?
            tracker.lock_breakeven!
            Rails.logger.info("[RiskManager] Breakeven locked for #{tracker.order_no} at #{pnl_pct_value.round(2)}% profit")
          end

          # Fallback to fixed threshold if adaptive schedule not available
          if drop_threshold < 100
            drop_pct = (hwm - pnl) / hwm
            if drop_pct >= drop_threshold
              reason = "TRAILING_STOP (fixed threshold: #{(drop_threshold * 100).round(2)}%, drop: #{(drop_pct * 100).round(2)}%)"
              exit_path = 'trailing_stop_fixed_upward'
              Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
              track_exit_path(tracker, exit_path, reason)
              dispatch_exit(exit_engine, tracker, reason)
              next
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

    def enforce_hard_limits(exit_engine:)
      risk = risk_config

      # HIGHEST PRIORITY: Hard rupee-based stops (check FIRST before %-based)
      if hard_rupee_sl_enabled? || hard_rupee_tp_enabled? || post_profit_zone_enabled?
        PositionTracker.active.find_each do |tracker|
          snapshot = pnl_snapshot(tracker)
          next unless snapshot

          net_pnl_rupees = snapshot[:pnl]
          next if net_pnl_rupees.nil?

          # For exit rule checks on active positions:
          # - Current net PnL = gross_pnl - entry_fee (₹20)
          # - After exit, final net PnL = gross_pnl - full_trade_fee (₹40)
          # - So: final_net_pnl = (net_pnl + entry_fee) - (entry_fee + exit_fee) = net_pnl - exit_fee
          # - We check if final_net_pnl will hit the target/stop after exit
          exit_fee = BrokerFeeCalculator.fee_per_order # Additional fee on exit (₹20)

          # Check secured profit zone SL (if in secured profit zone)
          if post_profit_zone_enabled? && tracker.meta&.dig('profit_zone_state') == 'secured_profit_zone'
            secured_sl_rupees = BigDecimal((tracker.meta&.dig('secured_sl_rupees') || post_profit_zone_config[:secured_sl_rupees] || 800).to_s)
            net_threshold = secured_sl_rupees + exit_fee
            if net_pnl_rupees < net_threshold
              final_net_pnl = net_pnl_rupees - exit_fee
              reason = "SECURED_PROFIT_SL (Current net: ₹#{net_pnl_rupees.round(2)}, Net after exit: ₹#{final_net_pnl.round(2)}, secured SL: ₹#{secured_sl_rupees})"
              exit_path = 'secured_profit_sl'
              Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
              track_exit_path(tracker, exit_path, reason)
              dispatch_exit(exit_engine, tracker, reason)
              next
            end
          end

          # Hard rupee stop loss (highest priority exit)
          # Apply session-aware SL multiplier
          if hard_rupee_sl_enabled?
            base_max_loss_rupees = BigDecimal((hard_rupee_sl_config[:max_loss_rupees] || 1000).to_s)
            # Apply time regime multiplier
            sl_multiplier = Live::TimeRegimeService.instance.sl_multiplier
            max_loss_rupees = base_max_loss_rupees * BigDecimal(sl_multiplier.to_s)
            net_threshold = -max_loss_rupees + exit_fee
            if net_pnl_rupees <= net_threshold
              # Calculate what net PnL will be after exit
              final_net_pnl = net_pnl_rupees - exit_fee
              reason = "HARD_RUPEE_SL (Current net: ₹#{net_pnl_rupees.round(2)}, Net after exit: ₹#{final_net_pnl.round(2)}, limit: -₹#{max_loss_rupees})"
              exit_path = 'hard_rupee_stop_loss'
              Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
              track_exit_path(tracker, exit_path, reason)
              dispatch_exit(exit_engine, tracker, reason)
              next
            end
          end

          # Hard rupee take profit - TRANSITION TO SECURED PROFIT ZONE (not immediate exit)
          # ₹2k TP is a minimum extraction, not a cap
          # After ₹2k, we transition to secured profit zone with green SL
          # PostProfitZoneRule will handle exits based on trend/momentum
          if hard_rupee_tp_enabled?
            base_target_profit_rupees = BigDecimal((hard_rupee_tp_config[:target_profit_rupees] || 2000).to_s)
            # Apply time regime multiplier
            tp_multiplier = Live::TimeRegimeService.instance.tp_multiplier
            target_profit_rupees = base_target_profit_rupees * BigDecimal(tp_multiplier.to_s)

            # Check session-specific max TP limit
            regime = Live::TimeRegimeService.instance.current_regime
            max_tp = Live::TimeRegimeService.instance.max_tp_rupees(regime)
            target_profit_rupees = [target_profit_rupees, BigDecimal((max_tp || 999_999).to_s)].min if max_tp

            net_threshold = target_profit_rupees + exit_fee

            if net_pnl_rupees >= net_threshold
              # Check if runners are allowed in current regime
              allow_runners = Live::TimeRegimeService.instance.allow_runners?(regime)

              if allow_runners
                # Transition to secured profit zone: Move SL to green
                transition_to_secured_profit_zone(tracker, net_pnl_rupees, target_profit_rupees)
                # Don't exit here - let PostProfitZoneRule handle exits based on trend/momentum
              else
                # No runners allowed - exit immediately
                final_net_pnl = net_pnl_rupees - exit_fee
                reason = "SESSION_TP_HIT (Current net: ₹#{net_pnl_rupees.round(2)}, Net after exit: ₹#{final_net_pnl.round(2)}, target: ₹#{target_profit_rupees}, regime: #{regime})"
                exit_path = 'session_take_profit'
                Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
                track_exit_path(tracker, exit_path, reason)
                dispatch_exit(exit_engine, tracker, reason)
              end
              next
            end
          end
        end
      end

      # Percentage-based stops (fallback/secondary)
      sl_pct = begin
        BigDecimal(risk[:sl_pct].to_s)
      rescue StandardError
        BigDecimal(0)
      end
      tp_pct = begin
        BigDecimal(risk[:tp_pct].to_s)
      rescue StandardError
        BigDecimal(0)
      end

      PositionTracker.active.find_each do |tracker|
        snapshot = pnl_snapshot(tracker)
        next unless snapshot

        pnl_pct = snapshot[:pnl_pct]
        next if pnl_pct.nil?

        # Convert pnl_pct from decimal (0.05) to percent (5.0) for DrawdownSchedule
        pnl_pct_value = pnl_pct.to_f * 100.0

        # Below-entry dynamic reverse SL (takes precedence over static sl_pct)
        if pnl_pct_value < 0
          seconds_below = seconds_below_entry(tracker)
          atr_ratio = calculate_atr_ratio(tracker)
          tracker.meta&.dig('index_key') || tracker.instrument&.symbol_name

          dyn_loss_pct = Positions::DrawdownSchedule.reverse_dynamic_sl_pct(
            pnl_pct_value,
            seconds_below_entry: seconds_below,
            atr_ratio: atr_ratio
          )

          if dyn_loss_pct && pnl_pct_value <= -dyn_loss_pct
            reason = "DYNAMIC_LOSS_HIT #{pnl_pct_value.round(2)}% (allowed: #{dyn_loss_pct.round(2)}%)"
            exit_path = 'stop_loss_adaptive_downward'
            Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path} (below_entry: #{seconds_below}s, atr_ratio: #{atr_ratio.round(3)})")
            track_exit_path(tracker, exit_path, reason)
            dispatch_exit(exit_engine, tracker, reason)
            next
          end
        end

        # Fallback to static SL if dynamic reverse_loss is disabled or not applicable
        # pnl_pct from Redis is a decimal (0.0193 = 1.93%), so multiply by 100 for display
        if pnl_pct <= -sl_pct
          pnl_pct_display = (pnl_pct * 100).round(2)
          reason = "SL HIT #{pnl_pct_display}%"
          exit_path = 'stop_loss_static_downward'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
          next
        end

        # Take Profit check
        # pnl_pct from Redis is a decimal (0.0573 = 5.73%), so multiply by 100 for display
        if pnl_pct >= tp_pct
          pnl_pct_display = (pnl_pct * 100).round(2)
          reason = "TP HIT #{pnl_pct_display}%"
          exit_path = 'take_profit'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
          next
        end

        # Upward drawdown check is now handled in enforce_trailing_stops() with adaptive schedule
        # Keeping this as fallback only if trailing is completely disabled
        # (Peak drawdown logic moved to enforce_trailing_stops for better organization)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_hard_limits error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
        Rails.logger.error("[RiskManager] Backtrace: #{e.backtrace.first(5).join(', ')}")
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
        if redis_pnl && redis_pnl[:ltp]
          cached = [{ ltp: redis_pnl[:ltp], timestamp: redis_pnl[:timestamp] || Time.current.to_i }]
        else
          cached = []
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

    def enforce_post_profit_zone(exit_engine:)
      return unless post_profit_zone_enabled?

      PositionTracker.active.find_each do |tracker|
        snapshot = pnl_snapshot(tracker)
        next unless snapshot

        pnl_rupees = snapshot[:pnl]
        next unless pnl_rupees&.positive?

        # Build rule context
        position_data = build_position_data_for_rule_engine(tracker, snapshot)
        context = Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: post_profit_zone_config
        )

        # Evaluate PostProfitZoneRule
        rule = Risk::Rules::PostProfitZoneRule.new(config: post_profit_zone_config)
        result = rule.evaluate(context)

        if result.exit?
          reason = result.reason || 'POST_PROFIT_ZONE_EXIT'
          exit_path = 'post_profit_zone'
          Rails.logger.info("[RiskManager] #{reason} for #{tracker.order_no} | Path: #{exit_path}")
          track_exit_path(tracker, exit_path, reason)
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_post_profit_zone error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
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

    private

    # Helper that centralizes exit dispatching logic.
    # If exit_engine is an object responding to execute_exit, delegate to it.
    # If exit_engine == self (or nil) we fallback to internal execute_exit implementation.
    def dispatch_exit(exit_engine, tracker, reason)
      if exit_engine && exit_engine.respond_to?(:execute_exit) && !exit_engine.equal?(self)
        begin
          exit_engine.execute_exit(tracker, reason)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] external exit_engine failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        end
      else
        # self-managed execution (backwards compatibility)
        execute_exit(tracker, reason)
      end
    end

    # --- Position/market helpers ---

    # Fetch live broker positions keyed by security_id (string). Returns {} on paper mode or failure.
    def fetch_positions_indexed
      return {} if paper_trading_enabled?

      positions = DhanHQ::Models::Position.active.each_with_object({}) do |position, map|
        security_id = position.respond_to?(:security_id) ? position.security_id : position[:security_id]
        map[security_id.to_s] = position if security_id
      end
      begin
        Live::FeedHealthService.instance.mark_success!(:positions)
      rescue StandardError
        nil
      end
      positions
    rescue StandardError => e
      Rails.logger.error("[RiskManager] fetch_positions_indexed failed: #{e.class} - #{e.message}")
      begin
        Live::FeedHealthService.instance.mark_failure!(:positions, error: e)
      rescue StandardError
        nil
      end
      {}
    end

    def paper_trading_enabled?
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
    rescue StandardError
      false
    end

    # Returns a cached pnl snapshot for tracker (expects Redis cache to be maintained elsewhere)
    def pnl_snapshot(tracker)
      Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
    rescue StandardError => e
      Rails.logger.error("[RiskManager] pnl_snapshot error for #{tracker.id}: #{e.class} - #{e.message}")
      nil
    end

    def update_paper_positions_pnl_if_due(last_update_time)
      # if last_update_time is nil or stale, update now
      return unless Time.current - (last_update_time || Time.zone.at(0)) >= 1.minute

      update_paper_positions_pnl
    rescue StandardError => e
      Rails.logger.error("[RiskManager] update_paper_positions_pnl_if_due failed: #{e.class} - #{e.message}")
    end

    # Update PnL for all paper trackers and cache in Redis (same semantics as before)
    def update_paper_positions_pnl
      paper_trackers = PositionTracker.paper.active.includes(:instrument).to_a
      return if paper_trackers.empty?

      paper_trackers.each do |tracker|
        next unless tracker.entry_price.present? && tracker.quantity.present?

        ltp = get_paper_ltp(tracker)
        unless ltp
          Rails.logger.debug { "[RiskManager] No LTP for paper tracker #{tracker.order_no}" }
          next
        end

        entry = BigDecimal(tracker.entry_price.to_s)
        exit_price = BigDecimal(ltp.to_s)
        qty = tracker.quantity.to_i
        gross_pnl = (exit_price - entry) * qty

        # Deduct broker fees (₹20 per order, ₹40 per trade if exited)
        pnl = BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: tracker.exited?)
        pnl_pct = entry.positive? ? ((exit_price - entry) / entry) : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil,
          high_water_mark_pnl: hwm
        )

        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] update_paper_positions_pnl failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end

      Rails.logger.info('[RiskManager] Paper PnL update completed')
    end

    # Ensure every active PositionTracker has an entry in Redis PnL cache (best-effort)
    # Throttled to avoid excessive queries - only runs every 5 seconds
    def ensure_all_positions_in_redis
      @last_ensure_all ||= Time.zone.at(0)
      return if Time.current - @last_ensure_all < 5.seconds

      trackers = PositionTracker.active.includes(:instrument).to_a
      return if trackers.empty?

      @last_ensure_all = Time.current

      positions = fetch_positions_indexed

      trackers.each do |tracker|
        redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
        next if redis_pnl && (Time.current.to_i - (redis_pnl[:timestamp] || 0)) < 10

        position = positions[tracker.security_id.to_s]
        tracker.hydrate_pnl_from_cache!

        ltp = if tracker.paper?
                get_paper_ltp(tracker)
              else
                current_ltp(tracker, position)
              end

        next unless ltp

        pnl = compute_pnl(tracker, position, ltp)
        next unless pnl

        pnl_pct = compute_pnl_pct(tracker, ltp, position)
        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] ensure_all_positions_in_redis failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end
    end

    # Compute current LTP (will try cache, API, tradable, etc.)
    def current_ltp(tracker, position = nil)
      return get_paper_ltp(tracker) if tracker.paper?

      if position.respond_to?(:exchange_segment) && position.exchange_segment == 'NSE_FNO'
        begin
          response = DhanHQ::Models::MarketFeed.ltp({ 'NSE_FNO' => [tracker.security_id.to_i] })
          if response['status'] == 'success'
            option_data = response.dig('data', 'NSE_FNO', tracker.security_id.to_s)
            if option_data && option_data['last_price']
              ltp = BigDecimal(option_data['last_price'].to_s)
              begin
                Live::RedisPnlCache.instance.store_tick(segment: 'NSE_FNO', security_id: tracker.security_id, ltp: ltp,
                                                        timestamp: Time.current)
              rescue StandardError
                nil
              end
              return ltp
            end
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] current_ltp(fetch option) failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        end
      end

      tradable = tracker.tradable
      return tradable.ltp if tradable && tradable.ltp

      segment = tracker.segment.presence || tracker.instrument&.exchange_segment
      cached = Live::TickCache.ltp(segment, tracker.security_id)
      return BigDecimal(cached.to_s) if cached

      fetch_ltp(position, tracker)
    end

    def get_paper_ltp(tracker)
      segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
      security_id = tracker.security_id
      return nil unless segment.present? && security_id.present?

      cached = Live::TickCache.ltp(segment, security_id)
      return BigDecimal(cached.to_s) if cached

      tick_data = begin
        Live::TickCache.fetch(segment, security_id)
      rescue StandardError
        nil
      end
      return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)

      tradable = tracker.tradable
      if tradable
        ltp = begin
          tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        rescue StandardError
          nil
        end
        return BigDecimal(ltp.to_s) if ltp
      end

      begin
        response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
        if response['status'] == 'success'
          option_data = response.dig('data', segment, security_id.to_s)
          return BigDecimal(option_data['last_price'].to_s) if option_data && option_data['last_price']
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] get_paper_ltp API error for #{tracker.order_no}: #{e.class} - #{e.message}")
      end

      nil
    end

    def fetch_ltp(position, tracker)
      segment = if position.respond_to?(:exchange_segment) then position.exchange_segment
                elsif position.is_a?(Hash) then position[:exchange_segment]
                end
      segment ||= tracker.instrument&.exchange_segment
      cached = begin
        Live::TickCache.ltp(segment, tracker.security_id)
      rescue StandardError
        nil
      end
      return BigDecimal(cached.to_s) if cached

      nil
    end

    def compute_pnl(tracker, position, ltp)
      if position.respond_to?(:net_qty) && position.respond_to?(:cost_price)
        quantity = position.net_qty.to_i
        cost_price = position.cost_price.to_f
        return nil if quantity.zero? || cost_price.zero?

        (ltp - BigDecimal(cost_price.to_s)) * quantity
      else
        quantity = tracker.quantity.to_i
        if quantity.zero? && position
          quantity = position.respond_to?(:quantity) ? position.quantity.to_i : (position[:quantity] || 0).to_i
        end
        return nil if quantity.zero?

        entry_price = tracker.entry_price || tracker.avg_price
        return nil if entry_price.blank?

        (ltp - BigDecimal(entry_price.to_s)) * quantity
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] compute_pnl failed for #{tracker.id}: #{e.class} - #{e.message}")
      nil
    end

    def compute_pnl_pct(tracker, ltp, position = nil)
      if position&.respond_to?(:cost_price)
        cost_price = position.cost_price.to_f
        return nil if cost_price.zero?

        (ltp - BigDecimal(cost_price.to_s)) / BigDecimal(cost_price.to_s)
      else
        entry_price = tracker.entry_price || tracker.avg_price
        return nil if entry_price.blank?

        (ltp - BigDecimal(entry_price.to_s)) / BigDecimal(entry_price.to_s)
      end
    rescue StandardError
      nil
    end

    def update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      return unless pnl && ltp && ltp.to_f.positive?

      Live::PnlUpdaterService.instance.cache_intermediate_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pnl_pct,
        ltp: ltp,
        hwm: tracker.high_water_mark_pnl
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] update_pnl_in_redis failed for #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    # --- Internal exit logic (fallback when no external ExitEngine provided) ---
    # Attempts to exit a tracker:
    # - For paper: update DB fields and return success
    # - For live: try Orders gateway (Orders.config.flat_position) or DhanHQ position methods
    def exit_position(_position, tracker)
      if tracker.paper?
        current_ltp_value = get_paper_ltp(tracker)
        unless current_ltp_value
          Rails.logger.warn("[RiskManager] Cannot get LTP for paper exit #{tracker.order_no}")
          return { success: false, exit_price: nil }
        end

        exit_price = BigDecimal(current_ltp_value.to_s)
        entry = begin
          BigDecimal(tracker.entry_price.to_s)
        rescue StandardError
          nil
        end
        qty = tracker.quantity.to_i
        gross_pnl = entry ? (exit_price - entry) * qty : nil

        # Deduct broker fees (₹20 per order, ₹40 per trade - position is being exited)
        pnl = gross_pnl ? BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: true) : nil
        # Calculate pnl_pct as decimal (0.0573 for 5.73%) for consistent DB storage (matches Redis format)
        pnl_pct = entry ? ((exit_price - entry) / entry) : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max if pnl

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil,
          high_water_mark_pnl: hwm,
          avg_price: exit_price
        )

        Rails.logger.info("[RiskManager] Paper exit simulated for #{tracker.order_no}: exit_price=#{exit_price}")
        return { success: true, exit_price: exit_price }
      end

      # Live exit flow: try Orders.config flat_position (recommended) -> DhanHQ SDK fallbacks
      begin
        segment = tracker.segment.presence || tracker.tradable&.exchange_segment || tracker.instrument&.exchange_segment
        unless segment.present?
          Rails.logger.error("[RiskManager] Cannot exit #{tracker.order_no}: no segment available")
          return { success: false, exit_price: nil }
        end

        if defined?(Orders) && Orders.respond_to?(:config) && Orders.config.respond_to?(:flat_position)
          order = Orders.config.flat_position(segment: segment, security_id: tracker.security_id)
          if order
            exit_price = current_ltp(tracker)
            exit_price = BigDecimal(exit_price.to_s) if exit_price
            return { success: true, exit_price: exit_price }
          end
        end

        # Fallback: try DhanHQ position convenience methods
        positions = fetch_positions_indexed
        position = positions[tracker.security_id.to_s]
        if position && position.respond_to?(:exit!)
          ok = position.exit!
          exit_price = begin
            current_ltp(tracker)
          rescue StandardError
            nil
          end
          return { success: ok, exit_price: exit_price }
        end

        Rails.logger.error("[RiskManager] Live exit failed for #{tracker.order_no} - no exit mechanism worked")
        { success: false, exit_price: nil }
      rescue StandardError => e
        Rails.logger.error("[RiskManager] exit_position error for #{tracker.order_no}: #{e.class} - #{e.message}")
        { success: false, exit_price: nil }
      end
    end

    # Persist reason metadata
    def store_exit_reason(tracker, reason)
      metadata = tracker.meta.is_a?(Hash) ? tracker.meta : {}
      tracker.update!(meta: metadata.merge('exit_reason' => reason, 'exit_triggered_at' => Time.current))
    rescue StandardError => e
      Rails.logger.warn("[RiskManager] store_exit_reason failed for #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    # Send Telegram exit notification
    # @param tracker [PositionTracker] Position tracker
    # @param reason [String] Exit reason
    # @param exit_price [BigDecimal, Float, nil] Exit price
    def notify_telegram_exit(tracker, reason, exit_price)
      return unless telegram_enabled?

      # Reload tracker to get final PnL
      tracker.reload if tracker.respond_to?(:reload)
      pnl = tracker.last_pnl_rupees

      Notifications::TelegramNotifier.instance.notify_exit(
        tracker,
        exit_reason: reason,
        exit_price: exit_price,
        pnl: pnl
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Telegram notification failed: #{e.class} - #{e.message}")
    end

    # Check if Telegram notifications are enabled
    # @return [Boolean]
    def telegram_enabled?
      config = AlgoConfig.fetch[:telegram] || {}
      enabled = config[:enabled] != false && config[:notify_exit] != false
      enabled && Notifications::TelegramNotifier.instance.enabled?
    rescue StandardError
      false
    end

    def parse_time_hhmm(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError
      Rails.logger.warn("[RiskManager] Invalid time format provided: #{value}")
      nil
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
      if cached
        # Update timestamp if still below entry
        Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
        (Time.current - cached).to_i
      else
        # First time below entry, initialize
        Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
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
      vwap = candles.any? ? candles.last(20).map(&:close).sum / candles.last(20).size : underlying_price

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

    def risk_config
      raw = begin
        AlgoConfig.fetch[:risk]
      rescue StandardError
        {}
      end
      return {} if raw.blank?

      cfg = raw.dup
      cfg[:stop_loss_pct] = raw[:stop_loss_pct] || raw[:sl_pct]
      cfg[:take_profit_pct] = raw[:take_profit_pct] || raw[:tp_pct]
      cfg[:sl_pct] = cfg[:stop_loss_pct]
      cfg[:tp_pct] = cfg[:take_profit_pct]
      cfg[:breakeven_after_gain] = raw.key?(:breakeven_after_gain) ? raw[:breakeven_after_gain] : 0
      cfg[:trail_step_pct] = raw[:trail_step_pct] if raw.key?(:trail_step_pct)
      cfg[:exit_drop_pct] = raw[:exit_drop_pct] if raw.key?(:exit_drop_pct)
      cfg[:time_exit_hhmm] = raw[:time_exit_hhmm] if raw.key?(:time_exit_hhmm)
      cfg[:market_close_hhmm] = raw[:market_close_hhmm] if raw.key?(:market_close_hhmm)
      cfg[:min_profit_rupees] = raw[:min_profit_rupees] if raw.key?(:min_profit_rupees)
      cfg
    rescue StandardError => e
      Rails.logger.error("[RiskManager] risk_config error: #{e.class} - #{e.message}")
      {}
    end

    def hard_rupee_sl_enabled?
      cfg = hard_rupee_sl_config
      cfg && cfg[:enabled] == true
    end

    def hard_rupee_tp_enabled?
      cfg = hard_rupee_tp_config
      cfg && cfg[:enabled] == true
    end

    def hard_rupee_sl_config
      AlgoConfig.fetch.dig(:risk, :hard_rupee_sl)
    rescue StandardError
      nil
    end

    def hard_rupee_tp_config
      AlgoConfig.fetch.dig(:risk, :hard_rupee_tp)
    rescue StandardError
      nil
    end

    def post_profit_zone_enabled?
      cfg = post_profit_zone_config
      cfg && cfg[:enabled] != false
    end

    def post_profit_zone_config
      raw = begin
        AlgoConfig.fetch.dig(:risk, :post_profit_zone) || {}
      rescue StandardError
        {}
      end

      # Defaults
      {
        enabled: true,
        secured_profit_threshold_rupees: raw[:secured_profit_threshold_rupees] || 2000,
        runner_zone_threshold_rupees: raw[:runner_zone_threshold_rupees] || 4000,
        secured_sl_rupees: raw[:secured_sl_rupees] || 800,
        underlying_adx_min: raw[:underlying_adx_min] || 18.0,
        option_pullback_max_pct: raw[:option_pullback_max_pct] || 35.0,
        underlying_atr_collapse_threshold: raw[:underlying_atr_collapse_threshold] || 0.65,
        runner_zone_momentum_check: raw[:runner_zone_momentum_check] || false
      }.merge(raw)
    end

    def transition_to_secured_profit_zone(tracker, net_pnl_rupees, target_profit_rupees)
      # Check if already transitioned
      return if tracker.meta&.dig('profit_zone_state') == 'secured_profit_zone'

      # Move SL to green (+₹500 to +₹1,000)
      secured_sl_config = post_profit_zone_config
      secured_sl_rupees = BigDecimal((secured_sl_config[:secured_sl_rupees] || 800).to_s)

      # Calculate entry price and quantity
      entry_price = tracker.entry_price
      quantity = tracker.quantity
      return unless entry_price && quantity && quantity.positive?

      # Calculate SL price that gives us secured_sl_rupees profit
      # Formula: (sl_price - entry_price) * quantity - exit_fee = secured_sl_rupees
      # sl_price = entry_price + (secured_sl_rupees + exit_fee) / quantity
      exit_fee = BrokerFeeCalculator.fee_per_order
      sl_price = entry_price + BigDecimal((secured_sl_rupees + exit_fee).to_s) / quantity

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
      return nil unless hwm && hwm.positive?

      entry_price = tracker.entry_price
      quantity = tracker.quantity
      return nil unless entry_price && quantity && quantity.positive?

      buy_value = entry_price * quantity
      return nil unless buy_value.positive?

      (hwm / buy_value).to_f
    end

    def iv_collapse_detection_enabled?
      config = begin
        AlgoConfig.fetch.dig(:risk, :time_overrides, :iv_collapse) || {}
      rescue StandardError
        {}
      end
      config[:enabled] == true
    end

    def stall_detection_enabled?
      config = stall_detection_config
      config[:enabled] == true
    end

    def stall_detection_config
      begin
        AlgoConfig.fetch.dig(:risk, :time_overrides, :stall_detection) || {}
      rescue StandardError
        {}
      end
    end

    # Record trade result in EdgeFailureDetector
    def record_trade_result_for_edge_detector(tracker, final_pnl, exit_reason)
      return unless tracker && final_pnl && exit_reason

      index_key = tracker.meta&.dig('index_key') || tracker.instrument&.symbol_name
      return unless index_key

      Live::EdgeFailureDetector.instance.record_trade_result(
        index_key: index_key,
        pnl_rupees: final_pnl.to_f,
        exit_reason: exit_reason.to_s,
        exit_time: Time.current
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] record_trade_result_for_edge_detector error: #{e.class} - #{e.message}")
    end

    def cancel_remote_order(order_id)
      order = DhanHQ::Models::Order.find(order_id)
      order.cancel
    rescue DhanHQ::Error => e
      Rails.logger.error("[RiskManager] cancel_remote_order DhanHQ error: #{e.message}")
      raise
    rescue StandardError => e
      Rails.logger.error("[RiskManager] cancel_remote_order unexpected error: #{e.class} - #{e.message}")
      raise
    end

    def pct_value(value)
      BigDecimal(value.to_s)
    rescue StandardError
      BigDecimal(0)
    end

    # Track exit path for analysis
    def track_exit_path(tracker, exit_path, reason)
      meta = tracker.meta || {}
      meta = {} unless meta.is_a?(Hash)

      direction = if exit_path.include?('upward')
                    'upward'
                  else
                    (exit_path.include?('downward') ? 'downward' : nil)
                  end
      type = if exit_path.include?('adaptive')
               'adaptive'
             else
               (exit_path.include?('fixed') ? 'fixed' : nil)
             end

      # Ensure entry metadata is preserved (in case it wasn't set during creation)
      # This is a safety net - entry metadata should already be set in EntryGuard
      entry_meta = {}
      unless meta['entry_path'] || meta['entry_strategy']
        # Try to find matching TradingSignal to get entry metadata
        signal = TradingSignal.where("metadata->>'index_key' = ?", meta['index_key'] || tracker.index_key)
                              .where('created_at >= ?', tracker.created_at - 5.minutes)
                              .where('created_at <= ?', tracker.created_at + 1.minute)
                              .order(created_at: :desc)
                              .first

        if signal && signal.metadata.is_a?(Hash)
          entry_meta['entry_path'] = signal.metadata['entry_path']
          entry_meta['entry_strategy'] = signal.metadata['strategy']
          entry_meta['entry_strategy_mode'] = signal.metadata['strategy_mode']
          entry_meta['entry_timeframe'] = signal.metadata['effective_timeframe'] || signal.metadata['primary_timeframe']
          entry_meta['entry_confirmation_timeframe'] = signal.metadata['confirmation_timeframe']
          entry_meta['entry_validation_mode'] = signal.metadata['validation_mode']
        end
      end

      tracker.update(
        meta: meta.merge(entry_meta).merge(
          'exit_path' => exit_path,
          'exit_reason' => reason,
          'exit_direction' => direction,
          'exit_type' => type,
          'exit_triggered_at' => Time.current
        )
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Failed to track exit path for #{tracker.order_no}: #{e.message}")
    end

    # Send Telegram exit notification
    # @param tracker [PositionTracker] Position tracker
    # @param reason [String] Exit reason
    # @param exit_price [BigDecimal, Float, nil] Exit price
    def notify_telegram_exit(tracker, reason, exit_price)
      return unless telegram_enabled?

      # Reload tracker to get final PnL
      tracker.reload if tracker.respond_to?(:reload)
      pnl = tracker.last_pnl_rupees

      Notifications::TelegramNotifier.instance.notify_exit(
        tracker,
        exit_reason: reason,
        exit_price: exit_price,
        pnl: pnl
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Telegram notification failed: #{e.class} - #{e.message}")
    end

    # Check if Telegram notifications are enabled
    # @return [Boolean]
    def telegram_enabled?
      config = AlgoConfig.fetch[:telegram] || {}
      enabled = config[:enabled] != false && config[:notify_exit] != false
      enabled && Notifications::TelegramNotifier.instance.enabled?
    rescue StandardError
      false
    end
  end
end
