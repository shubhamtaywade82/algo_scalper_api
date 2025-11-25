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

      @thread = Thread.new do
        Thread.current.name = 'risk-manager'
        last_paper_pnl_update = Time.current

        loop do
          break unless @running

          begin
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
    def monitor_loop(last_paper_pnl_update)
      # Keep Redis/DB PnL fresh
      update_paper_positions_pnl_if_due(last_paper_pnl_update)
      ensure_all_positions_in_redis

      # Ensure all active positions are in ActiveCache (for exit checking)
      ensure_all_positions_in_active_cache

      # Ensure all active positions are subscribed to market data
      ensure_all_positions_subscribed

      # NEW: Process trailing for all active positions (per-tick)
      # Peak-drawdown check happens FIRST inside TrailingEngine.process_tick()
      process_trailing_for_all_positions

      # Backwards-compatible enforcement: if there is no external ExitEngine, run enforcement here
      return unless @exit_engine.nil?

      enforce_hard_limits(exit_engine: self)
      enforce_trailing_stops(exit_engine: self)
      enforce_time_based_exit(exit_engine: self)
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

        redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
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
    def process_trailing_for_all_positions
      @bracket_placer ||= Orders::BracketPlacer.new
      @trailing_engine ||= Live::TrailingEngine.new(bracket_placer: @bracket_placer)

      active_cache = Positions::ActiveCache.instance
      positions = active_cache.all_positions
      return if positions.empty?

      tracker_map = trackers_for_positions(positions)
      trailing_exit_engine = @exit_engine

      positions.each do |position|
        tracker = tracker_map[position.tracker_id]
        next unless tracker&.active?

        ensure_position_snapshot(position)
        exit_engine = @exit_engine || self

        next if handle_underlying_exit(position, tracker, exit_engine)
        next if enforce_bracket_limits(position, tracker, exit_engine)

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
    def update_paper_positions_pnl
      paper_trackers = PositionTracker.paper.active.includes(:instrument).to_a
      return if paper_trackers.empty?

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

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct ? (pnl_pct * 100).round(2) : nil,
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

      PositionTracker.where(id: ids).index_by(&:id)
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
      return unless hub.enabled?

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
    def sync_position_pnl_from_redis(position, tracker)
      return unless position && tracker

      redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
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
      if redis_pnl[:ltp] && redis_pnl[:ltp].to_f.positive?
        position.current_ltp = redis_pnl[:ltp].to_f
      end

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
      @metrics[key] += 1
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
  end
end
