# frozen_string_literal: true

require 'singleton'
require 'monitor'
require 'bigdecimal'
require 'logger'

module Live
  class PnlUpdaterService
    include Singleton

    FLUSH_INTERVAL_SECONDS = 0.25
    MAX_BATCH = 200

    attr_reader :running

    def initialize
      @queue = {} # tracker_id => payload (last-wins)
      @mutex = Monitor.new
      @running = false
      @thread = nil
      @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
      @sleep_mutex = Mutex.new
      @sleep_cv = ConditionVariable.new
    end

    # Accept arbitrary payload fields; last-wins for a tracker id
    # Ensure all numeric fields are stored as BigDecimal (or nil)
    def cache_intermediate_pnl(tracker_id:, pnl: nil, pnl_pct: nil, ltp: nil, hwm: nil)
      @mutex.synchronize do
        @queue[tracker_id.to_i] = {
          pnl: safe_decimal(pnl),
          pnl_pct: safe_decimal(pnl_pct),
          ltp: safe_decimal(ltp),
          hwm: safe_decimal(hwm),
          updated_at: Time.now.to_i
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
      @logger.info('[PnlUpdater] started') if @logger
      loop do
        break unless running?

        processed = flush!
        sleep_duration = next_interval(queue_empty: !processed && queue_empty?)
        wait_for_interval(sleep_duration)
      end
    rescue StandardError => e
      @logger.error("[PnlUpdater] crashed: #{e.class} - #{e.message}")
      @running = false
    ensure
      @logger.info('[PnlUpdater] stopped') if @logger
    end

    def flush!
      batch = nil

      @mutex.synchronize do
        return false if @queue.empty?

        # Preserve insertion order, take first MAX_BATCH
        batch = @queue.first(MAX_BATCH).to_h

        # Remove processed keys
        batch.keys.each { |k| @queue.delete(k) }
      end

      return false unless batch && batch.any?

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

        # 1) Try TickCache (memory)
        tick_ltp = nil
        begin
          tick_ltp = Live::TickCache.ltp(seg, security_id)
        rescue StandardError => e
          @logger.warn("[PnlUpdater] TickCache.ltp error for #{seg}:#{security_id} - #{e.message}")
          tick_ltp = nil
        end

        # 2) RedisTickCache fallback
        if tick_ltp.nil? || (tick_ltp.respond_to?(:to_f) && tick_ltp.to_f <= 0)
          begin
            redis_tick = Live::RedisTickCache.instance.fetch_tick(seg, security_id)
            tick_ltp = redis_tick[:ltp] if redis_tick && redis_tick[:ltp].to_f.positive?
          rescue StandardError => e
            @logger.warn("[PnlUpdater] RedisTickCache.fetch_tick error for #{seg}:#{security_id} - #{e.message}")
            tick_ltp = nil
          end
        end

        # 3) Payload fallback
        if (tick_ltp.nil? || (tick_ltp.respond_to?(:to_f) && tick_ltp.to_f <= 0)) && payload[:ltp] && payload[:ltp].to_f.positive?
          tick_ltp = payload[:ltp]
        end

        unless tick_ltp && tick_ltp.to_f.positive?
          @logger.debug { "[PnlUpdater] Skip #{tracker_id}: no valid LTP (seg=#{seg} sid=#{security_id})" }
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

        # Compute PnL (fresh) — allow payload override when present (payload values are BigDecimal already)
        pnl_bd = payload[:pnl] || ((ltp_bd - entry_bd) * qty_bd)
        pnl_pct_bd = begin
          payload[:pnl_pct] || ((ltp_bd - entry_bd) / entry_bd)
        rescue StandardError
          BigDecimal(0)
        end

        hwm_bd = payload[:hwm] || (tracker.high_water_mark_pnl.present? ? safe_decimal(tracker.high_water_mark_pnl) : BigDecimal(0))
        hwm_bd = BigDecimal(0) if hwm_bd.nil?

        # Persist to Redis (use floats for storage to remain compatible)
        Live::RedisPnlCache.instance.store_pnl(
          tracker_id: tracker_id,
          pnl: pnl_bd.to_f,
          pnl_pct: pnl_pct_bd.to_f,
          ltp: ltp_bd.to_f,
          hwm: hwm_bd.to_f,
          timestamp: Time.now,
          tracker: tracker
        )

        # Update in-memory tracker object (but don't persist DB here)
        begin
          tracker.cache_live_pnl(pnl_bd, pnl_pct: pnl_pct_bd)
        rescue StandardError => e
          @logger.warn("[PnlUpdater] tracker.cache_live_pnl failed for #{tracker_id}: #{e.message}")
        end
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
  end
end
