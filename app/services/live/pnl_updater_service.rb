# frozen_string_literal: true

require 'singleton'
require 'concurrent'
require 'monitor'

module Live
  class PnlUpdaterService
    include Singleton

    # Tunables
    FLUSH_INTERVAL_SECONDS = 0.25
    MAX_BATCH = 200

    def initialize
      @queue = {} # tracker_id => payload (last-wins)
      @mutex = Monitor.new
      @running = false
      @thread = nil
    end

    # Called by RiskManagerService.update_pnl_in_redis and by other callers
    # Payload fields: tracker_id:, pnl:, pnl_pct:, ltp:, hwm:
    def cache_intermediate_pnl(tracker_id:, pnl:, pnl_pct: nil, ltp: nil, hwm: nil)
      @mutex.synchronize do
        @queue[tracker_id.to_i] = {
          pnl: BigDecimal(pnl.to_s),
          pnl_pct: pnl_pct.nil? ? nil : BigDecimal(pnl_pct.to_s),
          ltp: ltp.nil? ? nil : BigDecimal(ltp.to_s),
          hwm: hwm.nil? ? nil : BigDecimal(hwm.to_s),
          updated_at: Time.current.to_i
        }
      end

      start! unless running?
    rescue StandardError => e
      Rails.logger.error("[PnlUpdater] cache_intermediate_pnl error: #{e.class} - #{e.message}")
    end

    def start!
      return if running?

      @mutex.synchronize do
        return if running?

        @running = true
        @thread = Thread.new { run_loop }
        @thread.name = 'pnl-updater-service'
      end
    end

    def stop!
      @mutex.synchronize do
        @running = false
        if @thread&.alive?
          begin
            @thread.wakeup
          rescue StandardError
            nil
          end
        end
        @thread = nil
      end
    end

    def running?
      @running
    end

    private

    def run_loop
      Rails.logger.info('[PnlUpdater] started') if defined?(Rails.logger)
      loop do
        break unless running?

        flush!
        sleep FLUSH_INTERVAL_SECONDS
      end
    rescue StandardError => e
      Rails.logger.error("[PnlUpdater] crashed: #{e.class} - #{e.message}")
      @running = false
    ensure
      Rails.logger.info('[PnlUpdater] stopped') if defined?(Rails.logger)
    end

    def flush!
      batch = nil
      @mutex.synchronize do
        return if @queue.empty?

        # take up to MAX_BATCH items
        batch = @queue.shift(MAX_BATCH).to_h
      end
      return unless batch&.any?

      batch.each do |tracker_id, payload|
        # Load tracker to get segment/security_id and validate presence
        tracker = PositionTracker.find_by(id: tracker_id)
        unless tracker
          # orphaned tracker - clear from redis if any
          Live::RedisPnlCache.instance.clear_tracker(tracker_id)
          next
        end

        # Prefer canonical LTP from TickCache (fast & reliable)
        segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
        security_id = tracker.security_id.to_s

        ltp = nil
        # 1) prefer TickCache
        tick_ltp = begin
          Live::TickCache.ltp(segment, security_id)
        rescue StandardError
          nil
        end
        ltp = BigDecimal(tick_ltp.to_s) if tick_ltp&.to_f&.positive?

        # 2) fallback to payload.ltp if TickCache has nothing valid
        ltp = BigDecimal(payload[:ltp].to_s) if ltp.nil? && payload[:ltp] && payload[:ltp].to_f.positive?

        # If we don't have a valid positive LTP, skip writing to Redis (prevents 0 overwrites)
        unless ltp&.to_f&.positive?
          Rails.logger.debug { "[PnlUpdater] Skipping write for tracker #{tracker_id} - no valid LTP (tickcache/payload)" }
          next
        end

        # Recompute pnl_pct if missing using tracker.entry_price or payload
        pnl_value = payload[:pnl]
        pnl_pct = payload[:pnl_pct]
        if pnl_pct.nil? && tracker.entry_price.present? && tracker.entry_price.to_f.positive?
          begin
            pnl_pct = (ltp - BigDecimal(tracker.entry_price.to_s)) / BigDecimal(tracker.entry_price.to_s)
          rescue StandardError
            pnl_pct = nil
          end
        end

        hwm = payload[:hwm] || tracker.high_water_mark_pnl || BigDecimal(0)

        # Final write to Redis
        Live::RedisPnlCache.instance.store_pnl(
          tracker_id: tracker_id,
          pnl: pnl_value.to_f,
          pnl_pct: pnl_pct&.to_f,
          ltp: ltp.to_f,
          hwm: hwm.to_f,
          timestamp: Time.current
        )

        # Also update the AR model in-memory fields so callers reading `tracker.last_pnl_rupees` soon after see updated values
        tracker.cache_live_pnl(pnl_value, pnl_pct: pnl_pct) if pnl_value
      rescue StandardError => e
        Rails.logger.error("[PnlUpdater] Failed to flush tracker #{tracker_id}: #{e.class} - #{e.message}")
      end
    end
  end
end
