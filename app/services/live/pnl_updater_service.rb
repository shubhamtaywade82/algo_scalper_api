# frozen_string_literal: true

require 'singleton'
require 'monitor'
require 'bigdecimal'
require 'logger'
require_relative '../concerns/broker_fee_calculator'

module Live
  class PnlUpdaterService
    include Singleton

    FLUSH_INTERVAL_SECONDS = 0.25
    MAX_BATCH = 200
    PNL_STALE_DEBOUNCE_SECONDS = 5

    attr_reader :running

    def initialize
      @queue = {} # tracker_id => payload (last-wins)
      @mutex = Monitor.new
      @running = false
      @thread = nil
      @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout) # rubocop:disable Style/GlobalVars
      @sleep_mutex = Mutex.new
      @sleep_cv = ConditionVariable.new
      @last_heartbeat_at = nil
      @last_positions_keepalive_at = nil
    end

    # Accept arbitrary payload fields; last-wins for a tracker id
    # Ensure all numeric fields are stored as BigDecimal (or nil)
    def cache_intermediate_pnl(tracker_id:, pnl: nil, pnl_pct: nil, ltp: nil, hwm: nil, hwm_pnl_pct: nil)
      @mutex.synchronize do
        @queue[tracker_id.to_i] = {
          pnl: safe_decimal(pnl),
          pnl_pct: safe_decimal(pnl_pct),
          ltp: safe_decimal(ltp),
          hwm: safe_decimal(hwm),
          hwm_pnl_pct: safe_decimal(hwm_pnl_pct),
          updated_at: Time.current.to_i
        }
      end

      start! unless running?
      wake_up!
      true
    rescue StandardError => e
      @logger.error("[PnlUpdater] cache_intermediate_pnl error: #{e.class} - #{e.message}")
      false
    end

    def safe_decimal(value)
      return nil if value.nil?

      s = value.respond_to?(:to_s) ? value.to_s.strip : ''
      return nil if ['', ' '].include?(s)

      BigDecimal(s)
    rescue StandardError
      nil
    end

    def start!
      return true if running?

      @mutex.synchronize do
        return true if running?

        @running = true
        @thread = Thread.new { run_loop }
        begin
          @thread.name = 'pnl-updater-service'
        rescue StandardError
          # some Rubies don't allow thread name setting — ignore
        end
      end
      true
    end

    def stop!
      @mutex.synchronize do
        @running = false
        if @thread&.alive?
          begin
            @thread.wakeup
            @thread.join(1) # gently wait a bit
          rescue StandardError
            nil
          end
        end
        @thread = nil
        wake_up!
      end
    end

    def running?
      @running
    end

    # For tests/dev: force flush synchronously
    def flush_now!
      flush!
    end

    private

    def run_loop
      @logger&.info('[PnlUpdater] started')
      loop do
        break unless running?

        # Skip processing if market is closed and no active positions
        if TradingSession::Service.market_closed?
          # Use cached active positions to avoid redundant query
          active_count = Positions::ActivePositionsCache.instance.active_trackers.size
          if active_count.zero?
            # Market closed and no active positions - sleep longer
            sleep 60 # Check every minute when market is closed and no positions
            next
          end
          # Market closed but positions exist - continue processing (needed for PnL updates)
        end

        processed = flush!
        maybe_broadcast_heartbeat
        maybe_broadcast_positions_keepalive
        sleep_duration = next_interval(queue_empty: !processed && queue_empty?)
        wait_for_interval(sleep_duration)
      end
    rescue StandardError => e
      @logger.error("[PnlUpdater] crashed: #{e.class} - #{e.message}")
      @running = false
    ensure
      @logger&.info('[PnlUpdater] stopped')
    end

    def flush!
      batch = nil

      @mutex.synchronize do
        return false if @queue.empty?

        # Preserve insertion order, take first MAX_BATCH
        batch = @queue.first(MAX_BATCH).to_h

        # Remove processed keys
        batch.each_key { |k| @queue.delete(k) }
      end

      return false unless batch&.any?

      # Batch load all trackers in a single query to avoid N+1
      tracker_ids = batch.keys
      trackers_by_id = PositionTracker.includes(:watchable, :instrument).where(id: tracker_ids).index_by(&:id)

      batch.each do |tracker_id, payload|
        begin
          tracker = trackers_by_id[tracker_id]
        rescue StandardError => e
          @logger.error("[PnlUpdater] DB lookup failed for tracker #{tracker_id}: #{e.message}")
          begin
            Live::RedisPnlCache.instance.clear_tracker(tracker_id)
          rescue StandardError
            nil
          end
          next
        end

        unless tracker
          # No tracker => stale Redis entry must be cleared
          begin
            Live::RedisPnlCache.instance.clear_tracker(tracker_id)
          rescue StandardError
            nil
          end
          next
        end

        if tracker.exited?
          begin
            Live::RedisPnlCache.instance.clear_tracker(tracker_id)
          rescue StandardError
            nil
          end
          next
        end

        # Resolve segment reliably (match PositionTracker.subscribe logic)
        seg = (tracker.segment.presence ||
               tracker.watchable&.exchange_segment ||
               tracker.instrument&.exchange_segment ||
               tracker.instrument&.segment).to_s

        security_id = tracker.security_id.to_s

        if seg.blank? || security_id.blank?
          @logger.debug("[PnlUpdater] Skip #{tracker_id}: missing segment/security_id (seg=#{seg.inspect}, sid=#{security_id.inspect})")
          next
        end

        # 1) Try TickQuery facade (which handles memory + Redis fallback)
        tick_ltp = nil
        begin
          tick_ltp = Live::TickQuery.for_security(segment: seg, security_id: security_id)&.ltp
        rescue StandardError => e
          @logger.warn("[PnlUpdater] tick query error for #{seg}:#{security_id} - #{e.message}")
          tick_ltp = nil
        end

        # 3) Payload fallback
        if (tick_ltp.nil? || (tick_ltp.respond_to?(:to_f) && tick_ltp.to_f <= 0)) && payload[:ltp] && payload[:ltp].to_f.positive?
          tick_ltp = payload[:ltp]
        end

        unless tick_ltp&.to_f&.positive?
          @logger.debug { "[PnlUpdater] Skip #{tracker_id}: no valid LTP (seg=#{seg} sid=#{security_id})" }
          maybe_broadcast_pnl_stale(tracker_id)
          next
        end

        # Ensure entry_price & quantity exist and are numeric
        if tracker.entry_price.blank? || tracker.quantity.blank? || tracker.quantity.to_i <= 0
          @logger.warn("[PnlUpdater] Invalid tracker data for #{tracker_id} - entry_price=#{tracker.entry_price.inspect}, quantity=#{tracker.quantity.inspect}. Clearing redis key.")
          begin
            Live::RedisPnlCache.instance.clear_tracker(tracker_id)
          rescue StandardError
            nil
          end
          next
        end

        # Calculate with BigDecimal (all safe)
        ltp_bd = safe_decimal(tick_ltp) || BigDecimal(0)
        entry_bd = safe_decimal(tracker.entry_price) || BigDecimal(0)
        qty_bd = BigDecimal(tracker.quantity.to_i.to_s)

        # Compute gross PnL (fresh) — allow payload override when present (payload values are BigDecimal already)
        gross_pnl_bd = payload[:pnl] || ((ltp_bd - entry_bd) * qty_bd)

        # Deduct broker fees (₹20 per order, ₹40 per trade if exited)
        pnl_bd = BrokerFeeCalculator.net_pnl(gross_pnl_bd, is_exited: tracker.exited?)
        pnl_pct_bd = begin
          payload[:pnl_pct] || ((ltp_bd - entry_bd) / entry_bd)
        rescue StandardError
          BigDecimal(0)
        end

        # HWM: prefer payload, then Redis (real-time), then DB (stale up to 30s)
        hwm_bd = payload[:hwm]
        if hwm_bd.nil?
          redis_hwm = Live::RedisPnlCache.instance.fetch_pnl(tracker_id)&.dig(:hwm_pnl)
          hwm_bd = safe_decimal(redis_hwm) if redis_hwm
        end
        hwm_bd ||= (tracker.high_water_mark_pnl.present? ? safe_decimal(tracker.high_water_mark_pnl) : BigDecimal(0))
        hwm_bd = BigDecimal(0) if hwm_bd.nil?

        # Continuously update HWM from current PnL (don't wait for DB sync)
        hwm_bd = [hwm_bd, pnl_bd].max if pnl_bd.positive?

        # Calculate hwm_pnl_pct if not provided (Store as decimal, e.g. 0.05 for 5%)
        hwm_pnl_pct_bd = payload[:hwm_pnl_pct]
        if hwm_pnl_pct_bd.nil? && entry_bd.positive? && qty_bd.positive? && hwm_bd.positive?
          hwm_pnl_pct_bd = (hwm_bd / (entry_bd * qty_bd))
        end

        # Persist to Redis (use floats for storage to remain compatible)
        Live::RedisPnlCache.instance.store_pnl(
          tracker_id: tracker_id,
          pnl: pnl_bd.to_f,
          pnl_pct: pnl_pct_bd.to_f,
          ltp: ltp_bd.to_f,
          hwm: hwm_bd.to_f,
          hwm_pnl_pct: hwm_pnl_pct_bd.to_f,
          timestamp: Time.current,
          tracker: tracker
        )

        # Publish event for high-frequency risk evaluation
        Core::EventBus.instance.publish(:ltp, {
          tracker_id: tracker_id,
          ltp: ltp_bd.to_f,
          pnl: pnl_bd.to_f,
          pnl_pct: pnl_pct_bd.to_f,
          hwm: hwm_bd.to_f,
          timestamp: Time.current
        })

        broadcast_pnl_update(tracker_id, ltp_bd, pnl_bd, hwm_bd, entry_bd)

        # Update in-memory tracker object (but don't persist DB here)
        begin
          tracker.cache_live_pnl(pnl_bd, pnl_pct: pnl_pct_bd)
        rescue StandardError => e
          @logger.warn("[PnlUpdater] tracker.cache_live_pnl failed for #{tracker_id}: #{e.message}")
        end

        # Check for PnL milestones and send Telegram notifications
        check_and_notify_pnl_milestones(tracker, pnl_pct_bd, pnl_bd)
      rescue StandardError => e
        @logger.error("[PnlUpdater] processing failed for tracker #{tracker_id}: #{e.class} - #{e.message}")
        next
      end

      true
    end

    def queue_empty?
      @queue.empty?
    end

    def demand_driven_enabled?
      feature_flags[:enable_demand_driven_services] == true
    end

    def feature_flags
      AlgoConfig.fetch[:feature_flags] || {}
    rescue StandardError
      {}
    end

    def loop_intervals
      risk = AlgoConfig.fetch[:risk] || {}
      idle_ms = (risk[:loop_interval_idle] || 5000).to_i
      active_ms = (risk[:loop_interval_active] || (FLUSH_INTERVAL_SECONDS * 1000)).to_i
      [idle_ms.to_f / 1000.0, active_ms.to_f / 1000.0]
    rescue StandardError
      [5.0, FLUSH_INTERVAL_SECONDS]
    end

    def next_interval(queue_empty:)
      idle, active = loop_intervals
      if demand_driven_enabled? && queue_empty && Positions::ActiveCache.instance.empty?
        idle
      else
        active
      end
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

    # Check for PnL milestones and send notifications
    # @param tracker [PositionTracker] Position tracker
    # @param pnl_pct [BigDecimal] PnL as decimal (e.g. 0.05 for 5%)
    # @param pnl [BigDecimal] PnL value
    def check_and_notify_pnl_milestones(tracker, pnl_pct, pnl)
      return unless telegram_milestones_enabled?

      config = AlgoConfig.fetch[:telegram] || {}
      milestones = config[:pnl_milestones] || [10, 20, 30, 50, 100]
      pnl_pct_decimal = pnl_pct.to_f
      pnl_pct_as_percent = pnl_pct_decimal * 100.0

      # Get notified milestones from runtime cache (no per-milestone DB write)
      notified_milestones = Live::PositionRuntimeCache.instance.telegram_milestones_for(tracker)

      milestones.each do |milestone_pct|
        # Check if milestone reached (positive or negative); compare percentage to percentage
        milestone_reached = if pnl_pct_as_percent.positive?
                              pnl_pct_as_percent >= milestone_pct && notified_milestones.exclude?(milestone_pct)
                            elsif pnl_pct_as_percent.negative?
                              pnl_pct_as_percent <= -milestone_pct && notified_milestones.exclude?(-milestone_pct)
                            else
                              false
                            end

        next unless milestone_reached

        # Send notification (notifier expects pnl_pct in percentage, e.g. 5.0 for 5%)
        milestone_text = if pnl_pct_as_percent.positive?
                           "#{milestone_pct}% profit"
                         else
                           "#{milestone_pct}% loss"
                         end

        begin
          Notifications::TelegramNotifier.instance.notify_pnl_milestone(
            tracker,
            milestone: milestone_text,
            pnl: pnl,
            pnl_pct: pnl_pct_as_percent
          )

          # Mark milestone as notified (Redis only until exit flush)
          milestone_key = pnl_pct_as_percent.positive? ? milestone_pct : -milestone_pct
          Live::PositionRuntimeCache.instance.append_telegram_milestone!(tracker, milestone_key)
        rescue StandardError => e
          @logger.error("[PnlUpdater] Failed to notify milestone for #{tracker.id}: #{e.class} - #{e.message}")
        end
      end
    rescue StandardError => e
      @logger.error("[PnlUpdater] check_and_notify_pnl_milestones failed: #{e.class} - #{e.message}")
    end

    # Broadcast live PnL for a single position to the "positions" ActionCable channel.
    # pnl_pct is derived fresh from (ltp - entry) / entry * 100 to avoid ambiguity
    # around how callers store pnl_pct (decimal fraction vs percentage).
    def broadcast_pnl_update(tracker_id, ltp, pnl, hwm, entry)
      ltp_f   = ltp.to_f
      entry_f = entry.to_f
      pnl_pct = entry_f.positive? ? (((ltp_f - entry_f) / entry_f) * 100).round(2) : 0.0

      ActionCable.server.broadcast("positions", {
        type: "pnl_update",
        id: tracker_id,
        ltp: ltp_f.round(2),
        pnl: pnl.to_f.round(2),
        pnl_pct: pnl_pct,
        hwm_pnl: hwm.to_f.round(2),
        ltp_stale: false
      })
      begin
        Rails.cache.delete("pnl_stale:#{tracker_id}")
      rescue StandardError
        nil
      end
    rescue StandardError => e
      @logger.debug("[PnlUpdater] broadcast_pnl_update failed: #{e.message}")
    end

    # Notify the frontend that LTP (and thus live PnL) is stale for this tracker.
    # Debounced to avoid flooding the WS channel during cache outages.
    def maybe_broadcast_pnl_stale(tracker_id)
      return if tracker_id.blank?

      debounce_key = "pnl_stale:#{tracker_id}"
      return if Rails.cache&.read(debounce_key)

      Rails.cache&.write(debounce_key, true, expires_in: PNL_STALE_DEBOUNCE_SECONDS)
      ActionCable.server.broadcast("positions", { type: "pnl_stale", id: tracker_id })
    rescue StandardError => e
      @logger.debug("[PnlUpdater] maybe_broadcast_pnl_stale failed: #{e.message}")
    end

    # Broadcast aggregate dashboard stats every 1 second to the "dashboard" channel.
    def maybe_broadcast_heartbeat
      return if @last_heartbeat_at && (Time.current.to_f - @last_heartbeat_at) < 1.0

      @last_heartbeat_at = Time.current.to_f
      ActionCable.server.broadcast("dashboard", build_dashboard_stats)
    rescue StandardError => e
      @logger.debug("[PnlUpdater] heartbeat broadcast failed: #{e.message}")
    end

    # Keep the positions WS channel warm when ticks are quiet (illiquid strikes).
    def maybe_broadcast_positions_keepalive
      return if @last_positions_keepalive_at && (Time.current.to_f - @last_positions_keepalive_at) < 3.0
      return unless Positions::ActivePositionsCache.instance.active_trackers.any?

      @last_positions_keepalive_at = Time.current.to_f
      ActionCable.server.broadcast("positions", { type: 'keepalive', timestamp: Time.current.iso8601 })
    rescue StandardError => e
      @logger.debug("[PnlUpdater] positions keepalive broadcast failed: #{e.message}")
    end

    def build_dashboard_stats
      {
        type: "stats",
        mode: AlgoConfig.mode,
        balance: safe_wallet_snapshot,
        today: PositionTracker.trading_stats_with_pct,
        indices: {
          nifty: Live::TickCache.ltp('IDX_I', '13'),
          banknifty: Live::TickCache.ltp('IDX_I', '25'),
          sensex: Live::TickCache.ltp('IDX_I', '51')
        },
        circuit_breaker: Risk::CircuitBreaker.instance.status,
        system: Live::SystemStatusCache.instance.all_statuses.merge(
          pnl_updater_running: running?,
          ws_order_update: Live::OrderUpdateHub.instance.running?
        ),
        timestamp: Time.current.iso8601
      }
    rescue StandardError
      { type: "stats", error: true, timestamp: Time.current.iso8601 }
    end

    def safe_wallet_snapshot
      Orders.config.gateway.wallet_snapshot
    rescue StandardError
      { cash: 0, equity: 0, mtm: 0, exposure: 0 }
    end

    # Check if Telegram milestone notifications are enabled
    # @return [Boolean]
    def telegram_milestones_enabled?
      config = AlgoConfig.fetch[:telegram] || {}
      enabled = config[:enabled] != false && config[:notify_pnl_milestones] != false
      enabled && Notifications::TelegramNotifier.instance.enabled?
    rescue StandardError
      false
    end
  end
end
