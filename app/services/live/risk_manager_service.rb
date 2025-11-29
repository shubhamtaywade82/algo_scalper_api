# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'
require 'ostruct'

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
    MAX_RETRIES_ON_RATE_LIMIT = 3
    RATE_LIMIT_BACKOFF_BASE = 2.0 # seconds

    def initialize(exit_engine: nil, trailing_engine: nil)
      @exit_engine = exit_engine
      @trailing_engine = trailing_engine
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @last_api_call_time = Time.zone.at(0)
      @rate_limit_errors = {} # Track rate limit errors per segment:security_id
      @sleep_mutex = Mutex.new
      @sleep_cv = ConditionVariable.new
      @position_subscriptions = []
      @metrics = Hash.new(0)
      @redis_pnl_cache = {} # Per-cycle cache for Redis PnL lookups (cleared each cycle)
      @cycle_tracker_map = nil # Cached tracker map for current cycle

      # Phase 3: Circuit Breaker initialization
      @circuit_breaker_state = :closed # :closed, :open, :half_open
      @circuit_breaker_failures = 0
      @circuit_breaker_last_failure = nil
      @circuit_breaker_threshold = 5 # Open after 5 failures
      @circuit_breaker_timeout = 60 # Stay open for 60 seconds
      @started_at = nil # Track service start time for uptime

      # Watchdog ensures service thread is restarted if it dies (lightweight)
      @watchdog_thread = Thread.new do
        Thread.current.name = 'risk-manager-watchdog'
        loop do
          sleep 10
          # Only restart if service was running and thread is dead
          next unless @running && (@thread.nil? || !@thread.alive?)

          Rails.logger.warn('[RiskManagerService] Watchdog detected dead thread — restarting...')
          @running = false # Reset flag before restarting
          start
        end
      end

      subscribe_to_position_events
    end

    # Start monitoring loop (non-blocking)
    def start
      return if @running

      @running = true
      @started_at = Time.current

      @thread = Thread.new do
        Thread.current.name = 'risk-manager'
        last_paper_pnl_update = Time.current

        loop do
          break unless @running

          begin
            # Skip monitoring if market is closed and no active positions
            if TradingSession::Service.market_closed?
              active_count = PositionTracker.active.count
              if active_count.zero?
                # Market closed and no active positions - sleep longer
                sleep 60 # Check every minute when market is closed and no positions
                next
              end
              # Market closed but positions exist - continue monitoring (needed for exits)
            end

            if demand_driven_enabled? && Positions::ActiveCache.instance.empty?
              wait_for_interval(loop_sleep_interval(true))
              next
            end

            monitor_loop(last_paper_pnl_update)
            last_paper_pnl_update = Time.current
          rescue StandardError => e
            Rails.logger.error("[RiskManagerService] monitor_loop crashed: #{e.class} - #{e.message}\n#{e.backtrace.first(8).join("\n")}")
          end
          wait_for_interval(loop_sleep_interval(false))
        end
      end
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
      unsubscribe_from_position_events
      wake_up!
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
    # DO NOT perform exit dispatching here when an external ExitEngine exists — ExitEngine will call enforcement methods.
    # Phase 2: Consolidated iteration - processes all positions in single loop
    # Phase 3: Metrics tracking integrated
    def monitor_loop(last_paper_pnl_update)
      cycle_start_time = Time.current
      redis_fetches_before = @metrics[:total_redis_fetches] || 0
      db_queries_before = @metrics[:total_db_queries] || 0
      api_calls_before = @metrics[:total_api_calls] || 0
      exit_counts = {}
      error_counts = {}

      begin
        # Clear per-cycle caches at start of each cycle
        @redis_pnl_cache.clear
        @cycle_tracker_map = nil

        # Early exit if no positions (optimization)
        positions = active_cache_positions
        if positions.empty?
          # Still run maintenance tasks (throttled)
          update_paper_positions_pnl_if_due(last_paper_pnl_update)
          ensure_all_positions_in_redis
          ensure_all_positions_in_active_cache
          ensure_all_positions_subscribed
          # Record metrics for empty cycle before returning
          cycle_time = Time.current - cycle_start_time
          record_cycle_metrics(
            cycle_time: cycle_time,
            positions_count: 0,
            redis_fetches: 0,
            db_queries: 0,
            api_calls: 0,
            exit_counts: {},
            error_counts: {}
          )
          return
        end

        # Keep Redis/DB PnL fresh (throttled maintenance)
        update_paper_positions_pnl_if_due(last_paper_pnl_update)
        ensure_all_positions_in_redis

        # Ensure all active positions are in ActiveCache (for exit checking) - throttled
        ensure_all_positions_in_active_cache

        # Ensure all active positions are subscribed to market data - throttled
        ensure_all_positions_subscribed

        # Phase 2: Consolidated position processing - single iteration
        tracker_map = trackers_for_positions(positions)
        exit_engine = @exit_engine || self

        # Process all positions in single consolidated loop
        process_all_positions_in_single_loop(positions, tracker_map, exit_engine)

        # Backwards-compatible enforcement: if there is no external ExitEngine, run enforcement here
        # Note: Most enforcement is now handled in process_all_positions_in_single_loop
        # This is kept for fallback positions not in ActiveCache
        if @exit_engine.nil?
          enforce_hard_limits(exit_engine: self)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] monitor_loop error: #{e.class} - #{e.message}")
        error_counts[:monitor_loop_error] = (error_counts[:monitor_loop_error] || 0) + 1
        raise
      ensure
        # Phase 3: Record cycle metrics
        cycle_time = Time.current - cycle_start_time
        redis_fetches = (@metrics[:total_redis_fetches] || 0) - redis_fetches_before
        db_queries = (@metrics[:total_db_queries] || 0) - db_queries_before
        api_calls = (@metrics[:total_api_calls] || 0) - api_calls_before

        record_cycle_metrics(
          cycle_time: cycle_time,
          positions_count: positions&.length || 0,
          redis_fetches: redis_fetches,
          db_queries: db_queries,
          api_calls: api_calls,
          exit_counts: exit_counts,
          error_counts: error_counts
        )
      end
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

          # NEW: Record loss in DailyLimits if position exited with loss
          record_loss_if_applicable(tracker, exit_price)

          Rails.logger.info("[RiskManager] Successfully exited #{tracker.order_no} (#{tracker.id}) via internal executor")
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

    def enforce_trailing_stops(exit_engine:)
      risk = risk_config
      drop_threshold = begin
        BigDecimal(risk[:exit_drop_pct].to_s)
      rescue StandardError
        BigDecimal(0)
      end

      positions = active_cache_positions
      tracker_map = trackers_for_positions(positions)

      positions.each do |position|
        tracker = tracker_map[position.tracker_id]
        next unless tracker&.active?

        pnl = position.pnl
        hwm = position.high_water_mark
        next if pnl.nil? || hwm.nil? || hwm.zero?

        drop_pct = (hwm - pnl) / hwm
        next unless drop_pct >= drop_threshold

        reason = "TRAILING STOP drop=#{drop_pct.round(3)}"
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_trailing_stops error for tracker=#{tracker&.id}: #{e.class} - #{e.message}")
      end
    end

    def enforce_hard_limits(exit_engine:)
      risk = risk_config
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

      positions = active_cache_positions
      tracker_map = trackers_for_positions(positions)

      # Also check positions not in ActiveCache (fallback)
      # Load all trackers to find ones not in ActiveCache
      # Note: This is a fallback check, so we load fresh data
      all_trackers = PositionTracker.active.includes(:instrument).to_a
      trackers_not_in_cache = all_trackers.reject { |t| tracker_map[t.id] }

      positions.each do |position|
        tracker = tracker_map[position.tracker_id]
        next unless tracker&.active?

        # Sync PnL from Redis cache if ActiveCache is stale
        sync_position_pnl_from_redis(position, tracker)

        pnl_pct = position.pnl_pct
        next if pnl_pct.nil?

        normalized_pct = pnl_pct.to_f / 100.0

        if normalized_pct <= -sl_pct.to_f
          reason = "SL HIT #{pnl_pct.round(2)}%"
          dispatch_exit(exit_engine, tracker, reason)
          next
        end

        next unless normalized_pct >= tp_pct.to_f

        reason = "TP HIT #{pnl_pct.round(2)}%"
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_hard_limits error for tracker=#{tracker&.id}: #{e.class} - #{e.message}")
      end

      # Check positions not in ActiveCache using Redis PnL directly
      trackers_not_in_cache.each do |tracker|
        next unless tracker.active?

        # Use cached Redis PnL if available (from earlier in this cycle)
        redis_pnl = @redis_pnl_cache[tracker.id] ||= Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
        next unless redis_pnl && redis_pnl[:pnl_pct]

        pnl_pct = redis_pnl[:pnl_pct].to_f
        normalized_pct = pnl_pct / 100.0

        if normalized_pct <= -sl_pct.to_f
          reason = "SL HIT #{pnl_pct.round(2)}% (from Redis)"
          dispatch_exit(exit_engine, tracker, reason)
          next
        end

        next unless normalized_pct >= tp_pct.to_f

        reason = "TP HIT #{pnl_pct.round(2)}% (from Redis)"
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_hard_limits (fallback) error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end
    end

    # Enforce session end exit (before 3:15 PM IST)
    # This is separate from time-based exit and takes priority
    def enforce_session_end_exit(exit_engine:)
      session_check = TradingSession::Service.should_force_exit?
      return unless session_check[:should_exit]

      positions = active_cache_positions
      return if positions.empty?

      tracker_map = trackers_for_positions(positions)
      exited_count = 0

      positions.each do |position|
        tracker = tracker_map[position.tracker_id]
        next unless tracker&.active?

        # Sync PnL from Redis cache if ActiveCache is stale
        sync_position_pnl_from_redis(position, tracker)

        reason = 'session end (deadline: 3:15 PM IST)'
        dispatch_exit(exit_engine, tracker, reason)
        exited_count += 1
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_session_end_exit error for tracker=#{tracker&.id}: #{e.class} - #{e.message}")
      end

      Rails.logger.info("[RiskManager] Session end exit: #{exited_count} positions exited") if exited_count.positive?
    end

    def enforce_time_based_exit(exit_engine:)
      risk = risk_config
      exit_time = parse_time_hhmm(risk[:time_exit_hhmm] || '15:20')
      return unless exit_time

      now = Time.current
      return unless now >= exit_time

      market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
      return if market_close_time && now >= market_close_time

      positions = active_cache_positions
      tracker_map = trackers_for_positions(positions)

      positions.each do |position|
        tracker = tracker_map[position.tracker_id]
        next unless tracker&.active?

        # Sync PnL from Redis cache if ActiveCache is stale
        sync_position_pnl_from_redis(position, tracker)

        pnl_rupees = position.pnl
        if pnl_rupees.to_f.positive?
          min_profit = begin
            BigDecimal((risk[:min_profit_rupees] || 0).to_s)
          rescue StandardError
            BigDecimal(0)
          end
          if min_profit.positive? && BigDecimal(pnl_rupees.to_s) < min_profit
            Rails.logger.info("[RiskManager] Time-based exit skipped for #{tracker.order_no} - PnL < min_profit")
            next
          end
        end

        reason = "time-based exit (#{exit_time.strftime('%H:%M')})"
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_time_based_exit error for tracker=#{tracker&.id}: #{e.class} - #{e.message}")
      end
    end

    private

    # Process trailing stops for all active positions using TrailingEngine
    # Enhanced with underlying-aware exits and peak-drawdown gating
    def process_trailing_for_all_positions
      @bracket_placer ||= Orders::BracketPlacer.new
      @trailing_engine ||= Live::TrailingEngine.new(bracket_placer: @bracket_placer)

      active_cache = Positions::ActiveCache.instance
      positions = active_cache.all_positions
      return if positions.empty?

      tracker_map = trackers_for_positions(positions)
      trailing_exit_engine = @exit_engine || self

      positions.each do |position|
        tracker = tracker_map[position.tracker_id]
        next unless tracker&.active?

        ensure_position_snapshot(position)
        exit_engine = @exit_engine || self

        # 1. Recalculate PnL and peak (ensure fresh data)
        recalculate_position_metrics(position, tracker)

        # 2. Check underlying-aware exits FIRST (if enabled)
        next if handle_underlying_exit(position, tracker, exit_engine)

        # 3. Enforce hard SL/TP limits (always active)
        next if enforce_bracket_limits(position, tracker, exit_engine)

        # 4. Apply tiered trailing SL offsets
        desired_sl_offset_pct = Positions::TrailingConfig.sl_offset_for(position.pnl_pct)
        if desired_sl_offset_pct
          position.sl_offset_pct = desired_sl_offset_pct
          active_cache.update_position(position.tracker_id, sl_offset_pct: desired_sl_offset_pct)
        end

        # 5. Process trailing with peak-drawdown gating (via TrailingEngine)
        @trailing_engine.process_tick(position, exit_engine: trailing_exit_engine)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] TrailingEngine error for tracker #{position.tracker_id}: #{e.class} - #{e.message}")
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Error in process_trailing_for_all_positions: #{e.class} - #{e.message}")
    end

    # Record loss in DailyLimits if position exited with loss
    # @param tracker [PositionTracker] PositionTracker instance
    # @param exit_price [BigDecimal, Float, nil] Exit price
    def record_loss_if_applicable(tracker, exit_price)
      return unless tracker.entry_price && exit_price

      entry = tracker.entry_price.to_f
      exit = exit_price.to_f
      return unless entry.positive? && exit.positive?

      # Calculate PnL
      pnl = (exit - entry) * tracker.quantity.to_i
      return unless pnl.negative? # Only record losses

      # Get index key from tracker or instrument
      index_key = Positions::MetadataResolver.index_key(tracker)
      return unless index_key

      # Record loss in DailyLimits
      daily_limits = Live::DailyLimits.new
      daily_limits.record_loss(index_key: index_key, amount: pnl.abs)

      Rails.logger.info(
        "[RiskManager] Recorded loss for #{index_key}: ₹#{pnl.abs.round(2)} " \
        "(entry: ₹#{entry.round(2)}, exit: ₹#{exit.round(2)}, qty: #{tracker.quantity})"
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Failed to record loss: #{e.class} - #{e.message}")
    end

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
    # Phase 2: Uses batch LTP fetching for better performance
    def update_paper_positions_pnl
      paper_trackers = PositionTracker.paper.active.includes(:instrument).to_a
      return if paper_trackers.empty?

      # Phase 2: Use batch fetching for better performance
      if paper_trackers.length > 1
        batch_update_paper_positions_pnl(paper_trackers)
        return
      end

      # Fallback to individual calls for single tracker (backward compatibility)
      paper_trackers.each do |tracker|
        next unless tracker.entry_price.present? && tracker.quantity.present?

        # Stagger API calls to avoid rate limiting
        stagger_api_calls

        ltp = get_paper_ltp(tracker)
        unless ltp
          Rails.logger.debug { "[RiskManager] No LTP for paper tracker #{tracker.order_no}" }
          next
        end

        entry = BigDecimal(tracker.entry_price.to_s)
        exit_price = BigDecimal(ltp.to_s)
        qty = tracker.quantity.to_i
        pnl = (exit_price - entry) * qty
        pnl_pct = entry.positive? ? ((exit_price - entry) / entry) : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max
        hwm_pnl_pct = entry.positive? && qty.positive? ? ((hwm / (entry * qty)) * 100) : nil

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct ? (pnl_pct * 100).round(2) : nil,
          high_water_mark_pnl: hwm
        )

        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp, hwm_pnl_pct)
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

        # Stagger API calls to avoid rate limiting
        stagger_api_calls

        ltp = if tracker.paper?
                get_paper_ltp(tracker)
              else
                current_ltp(tracker, position)
              end

        next unless ltp

        pnl = compute_pnl(tracker, position, ltp)
        next unless pnl

        pnl_pct = compute_pnl_pct(tracker, ltp, position)

        # Calculate hwm_pnl_pct for ensure_all_positions_in_redis
        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max
        hwm_pnl_pct = if tracker.entry_price.present? && tracker.quantity.present?
                        entry = BigDecimal(tracker.entry_price.to_s)
                        qty = tracker.quantity.to_i
                        entry.positive? && qty.positive? ? ((hwm / (entry * qty)) * 100) : nil
                      end

        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp, hwm_pnl_pct)
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

      # Try WebSocket TickCache first (fastest, no API call)
      cached = Live::TickCache.ltp(segment, security_id)
      return BigDecimal(cached.to_s) if cached

      # Try RedisTickCache (cached from WebSocket or previous API calls)
      tick_data = begin
        Live::RedisTickCache.instance.fetch_tick(segment, security_id)
      rescue StandardError
        nil
      end
      return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)

      # Check if we're in rate limit cooldown for this security
      cache_key = "#{segment}:#{security_id}"
      if @rate_limit_errors[cache_key]
        last_error_time = @rate_limit_errors[cache_key][:last_error]
        backoff_seconds = @rate_limit_errors[cache_key][:backoff_seconds] || RATE_LIMIT_BACKOFF_BASE
        if Time.current - last_error_time < backoff_seconds
          Rails.logger.debug { "[RiskManager] Skipping API call for #{cache_key} (rate limit cooldown: #{backoff_seconds.round(1)}s)" }
          return nil
        end
      end

      # Try tradable's fetch method (may use cache)
      tradable = tracker.tradable
      if tradable
        ltp = begin
          tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        rescue StandardError => e
          handle_rate_limit_error(e, cache_key)
          nil
        end
        return BigDecimal(ltp.to_s) if ltp
      end

      # Last resort: Direct API call (with rate limiting)
      begin
        response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
        if response['status'] == 'success'
          option_data = response.dig('data', segment, security_id.to_s)
          if option_data && option_data['last_price']
            # Clear rate limit error on success
            @rate_limit_errors.delete(cache_key)
            return BigDecimal(option_data['last_price'].to_s)
          end
        end
      rescue StandardError => e
        handle_rate_limit_error(e, cache_key, tracker.order_no)
      end

      nil
    end

    # Stagger API calls to avoid rate limiting
    def stagger_api_calls
      @mutex.synchronize do
        elapsed = Time.current - @last_api_call_time
        sleep(API_CALL_STAGGER_SECONDS - elapsed) if elapsed < API_CALL_STAGGER_SECONDS
        @last_api_call_time = Time.current
      end
    end

    # Handle rate limit errors with exponential backoff
    def handle_rate_limit_error(error, cache_key, order_no = nil)
      error_msg = error.message.to_s
      is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit') || error.is_a?(DhanHQ::RateLimitError)

      if is_rate_limit
        # Exponential backoff: 2s, 4s, 8s, etc.
        current_backoff = @rate_limit_errors[cache_key]&.dig(:backoff_seconds) || RATE_LIMIT_BACKOFF_BASE
        retry_count = @rate_limit_errors[cache_key]&.dig(:retry_count) || 0

        if retry_count < MAX_RETRIES_ON_RATE_LIMIT
          new_backoff = current_backoff * 2
          @rate_limit_errors[cache_key] = {
            last_error: Time.current,
            backoff_seconds: new_backoff,
            retry_count: retry_count + 1
          }
          Rails.logger.warn("[RiskManager] Rate limit for #{cache_key} - backing off for #{new_backoff.round(1)}s (retry #{retry_count + 1}/#{MAX_RETRIES_ON_RATE_LIMIT})")
        else
          Rails.logger.error("[RiskManager] Rate limit exceeded max retries for #{cache_key} - skipping API calls")
        end
      else
        # Non-rate-limit error - log normally
        log_msg = order_no ? "get_paper_ltp API error for #{order_no}" : "get_paper_ltp API error for #{cache_key}"
        Rails.logger.error("[RiskManager] #{log_msg}: #{error.class} - #{error.message}")
      end
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
      if position && position.respond_to?(:cost_price)
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

    def update_pnl_in_redis(tracker, pnl, pnl_pct, ltp, hwm_pnl_pct = nil)
      return unless pnl && ltp && ltp.to_f.positive?

      # Calculate hwm_pnl_pct if not provided
      if hwm_pnl_pct.nil? && tracker.entry_price.present? && tracker.quantity.present?
        entry = BigDecimal(tracker.entry_price.to_s)
        qty = tracker.quantity.to_i
        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm_pnl_pct = entry.positive? && qty.positive? ? ((hwm / (entry * qty)) * 100) : nil
      end

      Live::PnlUpdaterService.instance.cache_intermediate_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pnl_pct,
        ltp: ltp,
        hwm: tracker.high_water_mark_pnl,
        hwm_pnl_pct: hwm_pnl_pct
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
        pnl = entry ? (exit_price - entry) * qty : nil
        pnl_pct = entry ? ((exit_price - entry) / entry) * 100 : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max if pnl

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct,
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

    def parse_time_hhmm(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError
      Rails.logger.warn("[RiskManager] Invalid time format provided: #{value}")
      nil
    end

    def active_cache_positions
      Positions::ActiveCache.instance.all_positions
    end

    def trackers_for_positions(position_list)
      ids = position_list.map(&:tracker_id).compact
      return {} if ids.empty?

      # Use cached tracker map if available and IDs match
      if @cycle_tracker_map
        cached_ids = @cycle_tracker_map.keys.map(&:to_i).to_set
        requested_ids = ids.map(&:to_i).to_set
        return @cycle_tracker_map if cached_ids == requested_ids
      end

      # Load trackers and cache for this cycle
      @cycle_tracker_map = PositionTracker.where(id: ids).includes(:instrument).index_by(&:id)
      @cycle_tracker_map
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

    def demand_driven_enabled?
      feature_flags[:enable_demand_driven_services] == true
    end

    def feature_flags
      AlgoConfig.fetch[:feature_flags] || {}
    rescue StandardError
      {}
    end

    def underlying_exits_enabled?
      feature_flags[:enable_underlying_aware_exits] == true
    end

    def ensure_position_snapshot(position)
      return if position.current_ltp&.positive?

      ltp = Live::TickCache.ltp(position.segment, position.security_id)
      unless ltp
        tick = Live::RedisTickCache.instance.fetch_tick(position.segment, position.security_id)
        ltp = tick[:ltp] if tick&.dig(:ltp)
      end
      position.update_ltp(ltp) if ltp
    rescue StandardError => e
      Rails.logger.error("[RiskManager] ensure_position_snapshot failed for tracker #{position.tracker_id}: #{e.class} - #{e.message}")
    end

    # Ensure all active positions are in ActiveCache
    def ensure_all_positions_in_active_cache
      @last_ensure_active_cache ||= Time.zone.at(0)
      return if Time.current - @last_ensure_active_cache < 5.seconds

      @last_ensure_active_cache = Time.current
      active_cache = Positions::ActiveCache.instance

      PositionTracker.active.find_each do |tracker|
        next unless tracker.entry_price&.positive?

        # Check if already in cache
        existing = active_cache.get_by_tracker_id(tracker.id)
        next if existing

        # Add to cache
        active_cache.add_position(tracker: tracker)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] ensure_all_positions_in_active_cache failed for tracker #{tracker.id}: #{e.class} - #{e.message}")
      end
    end

    # Ensure all active positions are subscribed to market data
    def ensure_all_positions_subscribed
      @last_ensure_subscribed ||= Time.zone.at(0)
      return if Time.current - @last_ensure_subscribed < 5.seconds

      @last_ensure_subscribed = Time.current
      hub = Live::MarketFeedHub.instance
      return unless hub.running?

      hub.start! unless hub.running?

      PositionTracker.active.find_each do |tracker|
        next unless tracker.security_id.present?

        segment_key = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
        next unless segment_key

        # Check if already subscribed
        next if hub.subscribed?(segment: segment_key, security_id: tracker.security_id)

        # Subscribe
        tracker.subscribe
      rescue StandardError => e
        Rails.logger.error("[RiskManager] ensure_all_positions_subscribed failed for tracker #{tracker.id}: #{e.class} - #{e.message}")
      end
    end

    # Sync position PnL from Redis cache to ActiveCache
    # This ensures exit conditions use the latest PnL data
    # Uses per-cycle cache to avoid redundant Redis fetches
    def sync_position_pnl_from_redis(position, tracker)
      return unless position && tracker

      # Use cached Redis PnL if available (fetched earlier in this cycle)
      redis_pnl = @redis_pnl_cache[tracker.id] ||= Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
      return unless redis_pnl && redis_pnl[:pnl]

      # Update ActiveCache position with Redis PnL data
      # Only update if Redis has fresher data (within last 30 seconds)
      redis_timestamp = redis_pnl[:timestamp] || 0
      return if (Time.current.to_i - redis_timestamp) > 30

      # Update PnL in ActiveCache
      position.pnl = redis_pnl[:pnl].to_f
      position.pnl_pct = redis_pnl[:pnl_pct].to_f if redis_pnl[:pnl_pct]
      position.high_water_mark = redis_pnl[:hwm_pnl].to_f if redis_pnl[:hwm_pnl]

      # Update LTP if available
      position.current_ltp = redis_pnl[:ltp].to_f if redis_pnl[:ltp] && redis_pnl[:ltp].to_f.positive?

      # Update peak profit if available
      if redis_pnl[:peak_profit_pct] && redis_pnl[:peak_profit_pct].to_f > (position.peak_profit_pct || 0)
        position.peak_profit_pct = redis_pnl[:peak_profit_pct].to_f
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] sync_position_pnl_from_redis failed for tracker #{tracker&.id}: #{e.class} - #{e.message}")
    end

    def handle_underlying_exit(position, tracker, exit_engine)
      return false unless underlying_exits_enabled?

      underlying_state = Live::UnderlyingMonitor.evaluate(position)
      return false unless underlying_state

      if structure_break_against_position?(position, tracker, underlying_state)
        log_underlying_exit(tracker, position, 'underlying_structure_break', underlying_state)
        increment_metric(:underlying_exit_count)
        guarded_exit(tracker, 'underlying_structure_break', exit_engine)
        return true
      end

      if underlying_state.trend_score &&
         underlying_state.trend_score.to_f < underlying_trend_score_threshold
        log_underlying_exit(tracker, position, 'underlying_trend_weak', underlying_state)
        increment_metric(:underlying_exit_count)
        guarded_exit(tracker, 'underlying_trend_weak', exit_engine)
        return true
      end

      if atr_collapse?(underlying_state)
        log_underlying_exit(tracker, position, 'underlying_atr_collapse', underlying_state)
        increment_metric(:underlying_exit_count)
        guarded_exit(tracker, 'underlying_atr_collapse', exit_engine)
        return true
      end

      false
    end

    def enforce_bracket_limits(position, tracker, exit_engine)
      return false unless position.current_ltp&.positive?

      if position.sl_hit?
        reason = format('SL HIT %.2f%%', position.pnl_pct.to_f)
        guarded_exit(tracker, reason, exit_engine)
        return true
      end

      if position.tp_hit?
        reason = format('TP HIT %.2f%%', position.pnl_pct.to_f)
        guarded_exit(tracker, reason, exit_engine)
        return true
      end

      false
    end

    def structure_break_against_position?(position, tracker, underlying_state)
      return false unless underlying_state&.bos_state == :broken

      direction = normalized_position_direction(position, tracker)
      (direction == :bullish && underlying_state.bos_direction == :bearish) ||
        (direction == :bearish && underlying_state.bos_direction == :bullish)
    end

    def normalized_position_direction(position, tracker)
      direction = position.position_direction
      return direction.to_s.downcase.to_sym if direction.present?

      Positions::MetadataResolver.direction(tracker)
    end

    def underlying_trend_score_threshold
      risk_config[:underlying_trend_score_threshold].to_f.positive? ? risk_config[:underlying_trend_score_threshold].to_f : 10.0
    end

    def underlying_atr_ratio_threshold
      value = risk_config[:underlying_atr_collapse_multiplier]
      value ? value.to_f : 0.65
    end

    def atr_collapse?(underlying_state)
      return false unless underlying_state

      underlying_state.atr_trend == :falling &&
        underlying_state.atr_ratio &&
        underlying_state.atr_ratio.to_f < underlying_atr_ratio_threshold
    end

    def log_underlying_exit(tracker, position, reason, underlying_state)
      Rails.logger.info(
        "[UNDERLYING_EXIT] reason=#{reason} tracker_id=#{tracker.id} order=#{tracker.order_no} " \
        "pnl_pct=#{position.pnl_pct&.round(2)} peak_pct=#{position.peak_profit_pct&.round(2)} " \
        "trend_score=#{underlying_state.trend_score} bos_state=#{underlying_state.bos_state} " \
        "bos_direction=#{underlying_state.bos_direction} atr_trend=#{underlying_state.atr_trend} " \
        "atr_ratio=#{underlying_state.atr_ratio} mtf_confirm=#{underlying_state.mtf_confirm}"
      )
    end

    def log_peak_drawdown_exit(tracker, position, drawdown)
      Rails.logger.warn(
        "[RiskManager] [PEAK_DRAWDOWN] tracker_id=#{tracker.id} order=#{tracker.order_no} " \
        "peak_pct=#{position.peak_profit_pct&.round(2)} current_pct=#{position.pnl_pct&.round(2)} " \
        "drawdown=#{drawdown.round(2)}%"
      )
    end

    def increment_metric(key)
      @mutex.synchronize do
        @metrics[key] += 1
      end
    end

    # Phase 3: Metrics & Monitoring

    # Record metrics for a single monitoring cycle
    #
    # @param cycle_time [Float] Time taken for the cycle in seconds
    # @param positions_count [Integer] Number of positions processed
    # @param redis_fetches [Integer] Number of Redis fetches
    # @param db_queries [Integer] Number of database queries
    # @param api_calls [Integer] Number of API calls made
    # @param exit_counts [Hash] Optional hash of exit type => count
    # @param error_counts [Hash] Optional hash of error type => count
    def record_cycle_metrics(cycle_time:, positions_count:, redis_fetches:, db_queries:, api_calls:, exit_counts: {}, error_counts: {})
      @mutex.synchronize do
        @metrics[:cycle_count] += 1
        @metrics[:total_cycle_time] += cycle_time
        @metrics[:min_cycle_time] = [@metrics[:min_cycle_time] || cycle_time, cycle_time].min
        @metrics[:max_cycle_time] = [@metrics[:max_cycle_time] || 0, cycle_time].max
        @metrics[:total_positions] += positions_count
        @metrics[:total_redis_fetches] += redis_fetches
        @metrics[:total_db_queries] += db_queries
        @metrics[:total_api_calls] += api_calls
        @metrics[:last_cycle_time] = cycle_time

        # Record exit counts
        exit_counts.each do |exit_type, count|
          @metrics[:"exit_#{exit_type}"] = (@metrics[:"exit_#{exit_type}"] || 0) + count
        end

        # Record error counts
        error_counts.each do |error_type, count|
          @metrics[:"error_#{error_type}"] = (@metrics[:"error_#{error_type}"] || 0) + count
        end
      end
    end

    # Get current metrics summary
    #
    # @return [Hash] Hash containing all metrics
    def get_metrics
      @mutex.synchronize do
        cycle_count = @metrics[:cycle_count] || 0

        base_metrics = {
          cycle_count: cycle_count,
          avg_cycle_time: cycle_count.positive? ? (@metrics[:total_cycle_time] || 0) / cycle_count : 0,
          min_cycle_time: @metrics[:min_cycle_time],
          max_cycle_time: @metrics[:max_cycle_time],
          total_cycle_time: @metrics[:total_cycle_time] || 0,
          avg_positions_per_cycle: cycle_count.positive? ? (@metrics[:total_positions] || 0) / cycle_count : 0,
          total_positions: @metrics[:total_positions] || 0,
          avg_redis_fetches_per_cycle: cycle_count.positive? ? (@metrics[:total_redis_fetches] || 0) / cycle_count : 0,
          total_redis_fetches: @metrics[:total_redis_fetches] || 0,
          avg_db_queries_per_cycle: cycle_count.positive? ? (@metrics[:total_db_queries] || 0) / cycle_count : 0,
          total_db_queries: @metrics[:total_db_queries] || 0,
          avg_api_calls_per_cycle: cycle_count.positive? ? (@metrics[:total_api_calls] || 0) / cycle_count : 0,
          total_api_calls: @metrics[:total_api_calls] || 0,
          exit_counts: @metrics.select { |k, _| k.to_s.start_with?('exit_') },
          error_counts: @metrics.select { |k, _| k.to_s.start_with?('error_') }
        }

        # Include individual exit and error metrics for easier access (already included in exit_counts/error_counts)
        # But also add them as top-level keys for convenience
        exit_error_metrics = @metrics.select { |k, _| k.to_s.start_with?('exit_') || k.to_s.start_with?('error_') }
        base_metrics.merge(exit_error_metrics)
      end
    end

    # Reset all metrics to zero
    def reset_metrics
      @mutex.synchronize do
        @metrics.clear
      end
    end

    # Phase 3: Circuit Breaker

    # Check if circuit breaker is open (blocking API calls)
    #
    # @param cache_key [String, nil] Optional cache key (for future per-key circuit breakers)
    # @return [Boolean] true if circuit breaker is open, false otherwise
    def circuit_breaker_open?(cache_key = nil)
      @mutex.synchronize do
        return false if @circuit_breaker_state == :closed

        if @circuit_breaker_state == :open
          # Check if timeout has passed
          if @circuit_breaker_last_failure &&
             (Time.current - @circuit_breaker_last_failure) > @circuit_breaker_timeout
            @circuit_breaker_state = :half_open
            @circuit_breaker_failures = 0
            return false
          end
          return true
        end

        # half_open state - allow one request to test
        false
      end
    end

    # Record an API failure (increment failure count, open circuit if threshold reached)
    #
    # @param cache_key [String, nil] Optional cache key (for future per-key circuit breakers)
    def record_api_failure(cache_key = nil)
      @mutex.synchronize do
        @circuit_breaker_failures += 1
        @circuit_breaker_last_failure = Time.current

        if @circuit_breaker_failures >= @circuit_breaker_threshold
          @circuit_breaker_state = :open
          Rails.logger.warn("[RiskManager] Circuit breaker OPEN - API failures: #{@circuit_breaker_failures}")
        end
      end
    end

    # Record an API success (close circuit if in half_open state)
    #
    # @param cache_key [String, nil] Optional cache key (for future per-key circuit breakers)
    def record_api_success(cache_key = nil)
      @mutex.synchronize do
        if @circuit_breaker_state == :half_open
          @circuit_breaker_state = :closed
          @circuit_breaker_failures = 0
          Rails.logger.info("[RiskManager] Circuit breaker CLOSED - API recovered")
        elsif @circuit_breaker_state == :open
          # Reset failures on success (but keep state as open until timeout)
          @circuit_breaker_failures = 0
        end
      end
    end

    # Reset circuit breaker to closed state (for testing or manual recovery)
    def reset_circuit_breaker
      @mutex.synchronize do
        @circuit_breaker_state = :closed
        @circuit_breaker_failures = 0
        @circuit_breaker_last_failure = nil
      end
    end

    # Phase 3: Health Status

    # Get health status of the service
    #
    # @return [Hash] Hash containing health status information
    def health_status
      @mutex.synchronize do
        {
          running: running?,
          thread_alive: @thread&.alive? || false,
          last_cycle_time: @metrics[:last_cycle_time],
          active_positions: PositionTracker.active.count,
          circuit_breaker_state: @circuit_breaker_state,
          recent_errors: @metrics[:recent_api_errors] || 0,
          uptime_seconds: running? && @started_at ? (Time.current - @started_at).to_i : 0
        }
      end
    end

    def guarded_exit(tracker, reason, exit_engine)
      if exit_engine && exit_engine.respond_to?(:execute_exit) && !exit_engine.equal?(self)
        return if tracker.exited?

        exit_engine.execute_exit(tracker, reason)
      else
        tracker.with_lock do
          return if tracker.exited?

          dispatch_exit(self, tracker, reason)
        end
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] guarded_exit failed for #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def loop_sleep_interval(active_cache_empty)
      interval_ms =
        if active_cache_empty
          risk_config[:loop_interval_idle] || 5000
        else
          risk_config[:loop_interval_active] || 500
        end
      interval_ms.to_f / 1000.0
    end

    def wait_for_interval(seconds)
      return sleep(seconds) unless demand_driven_enabled?

      @sleep_mutex.synchronize do
        @sleep_cv.wait(@sleep_mutex, seconds) if @running
      end
    end

    def wake_up!
      @sleep_mutex.synchronize do
        @sleep_cv.broadcast
      end
    end

    def subscribe_to_position_events
      return if @position_subscriptions.any?

      %w[positions.added positions.removed].each do |event|
        token = ActiveSupport::Notifications.subscribe(event) { wake_up! }
        @position_subscriptions << token
      end
    end

    def unsubscribe_from_position_events
      return if @position_subscriptions.empty?

      @position_subscriptions.each do |token|
        ActiveSupport::Notifications.unsubscribe(token)
      end
      @position_subscriptions.clear
    end

    # Phase 2: Process all positions in single consolidated loop
    # This eliminates 7-10 separate iterations over the same positions
    # @param positions [Array<Positions::ActiveCache::PositionData>] All active positions
    # @param tracker_map [Hash<Integer, PositionTracker>] Map of tracker_id => tracker
    # @param exit_engine [Object] Exit engine to use for exits
    def process_all_positions_in_single_loop(positions, tracker_map, exit_engine)
      positions.each do |position|
        tracker = tracker_map[position.tracker_id]
        next unless tracker&.active?

        begin
          # Sync PnL from Redis once per position (uses cycle cache)
          sync_position_pnl_from_redis(position, tracker)

          # Check all exit conditions in single pass (consolidated)
          next if check_all_exit_conditions(position, tracker, exit_engine)

          # Process trailing stops (if not exited)
          process_trailing_for_position(position, tracker, exit_engine)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] Error processing position #{position.tracker_id}: #{e.class} - #{e.message}")
        end
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Error in process_all_positions_in_single_loop: #{e.class} - #{e.message}")
    end

    # Phase 2: Check all exit conditions in single consolidated pass
    # Consolidates: session end, SL/TP, time-based, trailing stops
    # @param position [Positions::ActiveCache::PositionData] Position data
    # @param tracker [PositionTracker] PositionTracker instance
    # @param exit_engine [Object] Exit engine to use
    # @return [Boolean] true if exit was triggered, false otherwise
    def check_all_exit_conditions(position, tracker, exit_engine)
      # 1. Session end exit (highest priority)
      session_check = TradingSession::Service.should_force_exit?
      if session_check[:should_exit]
        dispatch_exit(exit_engine, tracker, 'session end (deadline: 3:15 PM IST)')
        return true
      end

      # 2. Hard limits (SL/TP) - consolidated check
      if check_sl_tp_limits(position, tracker, exit_engine)
        return true
      end

      # 3. Time-based exit
      if check_time_based_exit(position, tracker, exit_engine)
        return true
      end

      false
    rescue StandardError => e
      Rails.logger.error("[RiskManager] check_all_exit_conditions error for tracker #{tracker&.id}: #{e.class} - #{e.message}")
      false
    end

    # Phase 2: Consolidated SL/TP limit check
    # @param position [Positions::ActiveCache::PositionData] Position data
    # @param tracker [PositionTracker] PositionTracker instance
    # @param exit_engine [Object] Exit engine to use
    # @return [Boolean] true if exit was triggered, false otherwise
    def check_sl_tp_limits(position, tracker, exit_engine)
      risk = risk_config
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

      pnl_pct = position.pnl_pct
      return false if pnl_pct.nil?

      normalized_pct = pnl_pct.to_f / 100.0

      if normalized_pct <= -sl_pct.to_f
        reason = "SL HIT #{pnl_pct.round(2)}%"
        dispatch_exit(exit_engine, tracker, reason)
        return true
      end

      if normalized_pct >= tp_pct.to_f
        reason = "TP HIT #{pnl_pct.round(2)}%"
        dispatch_exit(exit_engine, tracker, reason)
        return true
      end

      false
    rescue StandardError => e
      Rails.logger.error("[RiskManager] check_sl_tp_limits error for tracker #{tracker&.id}: #{e.class} - #{e.message}")
      false
    end

    # Phase 2: Time-based exit check
    # @param position [Positions::ActiveCache::PositionData] Position data
    # @param tracker [PositionTracker] PositionTracker instance
    # @param exit_engine [Object] Exit engine to use
    # @return [Boolean] true if exit was triggered, false otherwise
    def check_time_based_exit(position, tracker, exit_engine)
      risk = risk_config
      exit_time = parse_time_hhmm(risk[:time_exit_hhmm] || '15:20')
      return false unless exit_time

      now = Time.current
      return false unless now >= exit_time

      market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
      return false if market_close_time && now >= market_close_time

      pnl_rupees = position.pnl
      if pnl_rupees.to_f.positive?
        min_profit = begin
          BigDecimal((risk[:min_profit_rupees] || 0).to_s)
        rescue StandardError
          BigDecimal(0)
        end
        if min_profit.positive? && BigDecimal(pnl_rupees.to_s) < min_profit
          Rails.logger.info("[RiskManager] Time-based exit skipped for #{tracker.order_no} - PnL < min_profit")
          return false
        end
      end

      reason = "time-based exit (#{exit_time.strftime('%H:%M')})"
      dispatch_exit(exit_engine, tracker, reason)
      true
    rescue StandardError => e
      Rails.logger.error("[RiskManager] check_time_based_exit error for tracker #{tracker&.id}: #{e.class} - #{e.message}")
      false
    end

    # Phase 2: Process trailing for single position
    # @param position [Positions::ActiveCache::PositionData] Position data
    # @param tracker [PositionTracker] PositionTracker instance
    # @param exit_engine [Object] Exit engine to use
    def process_trailing_for_position(position, tracker, exit_engine)
      @bracket_placer ||= Orders::BracketPlacer.new
      @trailing_engine ||= Live::TrailingEngine.new(bracket_placer: @bracket_placer)

      ensure_position_snapshot(position)

      # Recalculate position metrics (PnL, peak) from current LTP
      recalculate_position_metrics(position, tracker)

      # Check underlying-aware exits FIRST (if enabled)
      return if handle_underlying_exit(position, tracker, exit_engine)

      # Enforce hard SL/TP limits (always active) - already checked in check_all_exit_conditions
      # but check again here for bracket limits
      return if enforce_bracket_limits(position, tracker, exit_engine)

      # Apply tiered trailing SL offsets
      desired_sl_offset_pct = Positions::TrailingConfig.sl_offset_for(position.pnl_pct)
      if desired_sl_offset_pct
        position.sl_offset_pct = desired_sl_offset_pct
        active_cache = Positions::ActiveCache.instance
        active_cache.update_position(position.tracker_id, sl_offset_pct: desired_sl_offset_pct)
      end

      # Process trailing with peak-drawdown gating (via TrailingEngine)
      trailing_exit_engine = exit_engine
      @trailing_engine.process_tick(position, exit_engine: trailing_exit_engine)
    rescue StandardError => e
      Rails.logger.error("[RiskManager] process_trailing_for_position error for tracker #{position.tracker_id}: #{e.class} - #{e.message}")
    end

    # Phase 2: Batch fetch LTP for multiple positions
    # Groups positions by segment and makes single API call per segment
    # @param security_ids_by_segment [Array<Hash>] Array of {segment:, security_id:} hashes
    # @return [Hash<String, BigDecimal>] Map of security_id => LTP
    def batch_fetch_ltp(security_ids_by_segment)
      return {} if security_ids_by_segment.empty?

      # Phase 3: Check circuit breaker before making API calls
      if circuit_breaker_open?
        Rails.logger.warn("[RiskManager] Circuit breaker OPEN - skipping batch_fetch_ltp")
        @metrics[:recent_api_errors] = (@metrics[:recent_api_errors] || 0) + 1
        return {}
      end

      # Group by segment
      grouped = security_ids_by_segment.group_by { |item| item[:segment] }
      result = {}

      grouped.each do |segment, items|
        security_ids = items.map { |item| item[:security_id].to_i }

        begin
          # Single API call for all security_ids in this segment
          @metrics[:total_api_calls] = (@metrics[:total_api_calls] || 0) + 1
          response = DhanHQ::Models::MarketFeed.ltp({ segment => security_ids })

          if response['status'] == 'success'
            # Phase 3: Record API success
            record_api_success

            segment_data = response.dig('data', segment) || {}
            items.each do |item|
              security_id_str = item[:security_id].to_s
              option_data = segment_data[security_id_str]
              if option_data && option_data['last_price']
                ltp = BigDecimal(option_data['last_price'].to_s)
                result[security_id_str] = ltp

                # Store in Redis tick cache
                begin
                  Live::RedisPnlCache.instance.store_tick(
                    segment: segment,
                    security_id: item[:security_id],
                    ltp: ltp,
                    timestamp: Time.current
                  )
                rescue StandardError
                  nil
                end
              end
            end
          else
            # Phase 3: Record API failure for non-success response
            record_api_failure
            @metrics[:recent_api_errors] = (@metrics[:recent_api_errors] || 0) + 1
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] batch_fetch_ltp failed for segment #{segment}: #{e.class} - #{e.message}")
          # Phase 3: Record API failure
          record_api_failure
          @metrics[:recent_api_errors] = (@metrics[:recent_api_errors] || 0) + 1

          # Fallback: try individual calls for this segment
          items.each do |item|
            begin
              ltp = get_paper_ltp_for_security(item[:segment], item[:security_id])
              result[item[:security_id].to_s] = ltp if ltp
            rescue StandardError
              nil
            end
          end
        end
      end

      result
    end

    # Helper for individual LTP fetch (fallback)
    def get_paper_ltp_for_security(segment, security_id)
      # Try WebSocket TickCache first
      cached = Live::TickCache.ltp(segment, security_id)
      return BigDecimal(cached.to_s) if cached

      # Try RedisTickCache
      tick_data = begin
        Live::RedisTickCache.instance.fetch_tick(segment, security_id)
      rescue StandardError
        nil
      end
      return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)

      # Phase 3: Check circuit breaker before making API call
      if circuit_breaker_open?
        Rails.logger.warn("[RiskManager] Circuit breaker OPEN - skipping get_paper_ltp_for_security")
        @metrics[:recent_api_errors] = (@metrics[:recent_api_errors] || 0) + 1
        return nil
      end

      # Direct API call
      begin
        @metrics[:total_api_calls] = (@metrics[:total_api_calls] || 0) + 1
        response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
        if response['status'] == 'success'
          # Phase 3: Record API success
          record_api_success

          option_data = response.dig('data', segment, security_id.to_s)
          if option_data && option_data['last_price']
            return BigDecimal(option_data['last_price'].to_s)
          end
        else
          # Phase 3: Record API failure for non-success response
          record_api_failure
          @metrics[:recent_api_errors] = (@metrics[:recent_api_errors] || 0) + 1
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] get_paper_ltp_for_security failed: #{e.class} - #{e.message}")
        # Phase 3: Record API failure
        record_api_failure
        @metrics[:recent_api_errors] = (@metrics[:recent_api_errors] || 0) + 1
      end

      nil
    end

    # Phase 2: Batch update paper positions PnL using batch LTP fetching
    # @param trackers [Array<PositionTracker>] Paper trackers to update
    def batch_update_paper_positions_pnl(trackers)
      return if trackers.empty?

      # Prepare security IDs for batch fetch
      security_ids_by_segment = trackers.map do |tracker|
        segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
        next unless segment.present? && tracker.security_id.present?

        { segment: segment, security_id: tracker.security_id }
      end.compact

      # Batch fetch LTPs
      ltps = batch_fetch_ltp(security_ids_by_segment)

      # Update each tracker with batched LTP
      pnl_updater = Live::PnlUpdaterService.instance
      trackers.each do |tracker|
        next unless tracker.entry_price.present? && tracker.quantity.present?

        ltp = ltps[tracker.security_id.to_s]
        next unless ltp

        entry = BigDecimal(tracker.entry_price.to_s)
        exit_price = BigDecimal(ltp.to_s)
        qty = tracker.quantity.to_i
        pnl = (exit_price - entry) * qty
        pnl_pct = entry.positive? ? ((exit_price - entry) / entry) : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max
        hwm_pnl_pct = entry.positive? && qty.positive? ? ((hwm / (entry * qty)) * 100) : nil

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct ? (pnl_pct * 100).round(2) : nil,
          high_water_mark_pnl: hwm
        )

        pnl_updater.cache_intermediate_pnl(
          tracker_id: tracker.id,
          pnl: pnl,
          pnl_pct: pnl_pct,
          ltp: ltp,
          hwm: hwm,
          hwm_pnl_pct: hwm_pnl_pct
        )
      rescue StandardError => e
        Rails.logger.error("[RiskManager] batch_update_paper_positions_pnl failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end

      Rails.logger.info('[RiskManager] Batch paper PnL update completed')
    end

    # Recalculate position metrics (PnL, peak) from current LTP
    # @param position [Positions::ActiveCache::PositionData] Position data
    # @param tracker [PositionTracker] PositionTracker instance
    def recalculate_position_metrics(position, tracker)
      return unless position && tracker

      # Sync from Redis cache first (most up-to-date)
      # Uses per-cycle cache to avoid redundant fetches
      sync_position_pnl_from_redis(position, tracker)

      # Ensure LTP is current
      ensure_position_snapshot(position)

      # Recalculate if needed
      if position.current_ltp&.positive? && position.entry_price&.positive?
        position.recalculate_pnl
        # Update peak if current exceeds it
        if position.pnl_pct && position.peak_profit_pct && position.pnl_pct > position.peak_profit_pct
          active_cache = Positions::ActiveCache.instance
          active_cache.update_position(position.tracker_id, peak_profit_pct: position.pnl_pct)
        end
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] recalculate_position_metrics failed for tracker #{tracker&.id}: #{e.class} - #{e.message}")
    end
  end
end
