# frozen_string_literal: true

require 'singleton'

module Live
  # ReconciliationService ensures data consistency across:
  # - PositionTracker (Database)
  # - Redis PnL Cache
  # - ActiveCache (in-memory)
  # - MarketFeedHub subscriptions
  #
  # Runs periodically to detect and auto-correct inconsistencies
  class ReconciliationService
    include Singleton

    # Increased interval to reduce redundancy with RiskManagerService
    # RiskManagerService already ensures caches every 5 seconds
    # This service is primarily for on-demand reconciliation
    RECONCILIATION_INTERVAL = 30.seconds

    def initialize
      @last_reconciliation = nil
      @stats = {
        reconciliations: 0,
        positions_fixed: 0,
        subscriptions_fixed: 0,
        activecache_fixed: 0,
        pnl_synced: 0,
        errors: 0
      }
    end

    def start
      return if @running

      @running = true
      @thread = Thread.new do
        Thread.current.name = 'reconciliation-service'
        run_loop
      end
      Rails.logger.info('[ReconciliationService] Started')
    end

    def stop
      @running = false
      @thread&.join(2)
      @thread = nil
      Rails.logger.info('[ReconciliationService] Stopped')
    end

    def running?
      @running && @thread&.alive?
    end

    def stats
      @stats.dup
    end

    private

    def run_loop
      loop do
        break unless @running

        begin
          # Skip reconciliation if market is closed and no active positions
          if TradingSession::Service.market_closed?
            # Use cached active positions to avoid redundant query
            active_count = Positions::ActivePositionsCache.instance.active_trackers.size
            if active_count.zero?
              # Market closed and no active positions - no need to reconcile
              # Sleep longer to reduce CPU usage
              sleep 60 # Check every minute when market is closed and no positions
              next
            end
            # Market closed but positions exist - continue reconciliation
            # (still need to monitor for exits and data consistency)
          end

          reconcile_all_positions if should_reconcile?
        rescue StandardError => e
          @stats[:errors] += 1
          Rails.logger.error("[ReconciliationService] Error in run_loop: #{e.class} - #{e.message}")
          Rails.logger.debug { e.backtrace.first(5).join("\n") }
        end

        sleep 1 # Check every second, but only reconcile every 30 seconds (reduced redundancy)
      end
    rescue StandardError => e
      Rails.logger.error("[ReconciliationService] Fatal error: #{e.class} - #{e.message}")
      @running = false
    end

    def should_reconcile?
      return true if @last_reconciliation.nil?
      return false if Time.current - @last_reconciliation < RECONCILIATION_INTERVAL

      true
    end

    def reconcile_all_positions
      @last_reconciliation = Time.current
      @stats[:reconciliations] += 1

      active_trackers = Positions::ActivePositionsCache.instance.active_trackers
      return if active_trackers.empty?

      hub = Live::MarketFeedHub.instance
      active_cache = Positions::ActiveCache.instance
      redis_cache = Live::RedisPnlCache.instance

      active_trackers.each do |tracker|
        reconcile_position(tracker, hub, active_cache, redis_cache)
      rescue StandardError => e
        @stats[:errors] += 1
        Rails.logger.error("[ReconciliationService] Failed to reconcile tracker #{tracker.id}: #{e.class} - #{e.message}")
      end
    end

    def reconcile_position(tracker, hub, active_cache, redis_cache)
      fixes_applied = []

      # 1. Ensure subscribed
      unless subscribed?(tracker, hub)
        fix_subscription(tracker, hub)
        fixes_applied << :subscription
        @stats[:subscriptions_fixed] += 1
      end

      # 2. Ensure in ActiveCache
      unless in_active_cache?(tracker, active_cache)
        fix_active_cache(tracker, active_cache)
        fixes_applied << :activecache
        @stats[:activecache_fixed] += 1
      end

      # 3. Sync PnL from Redis to DB
      if pnl_needs_sync?(tracker, redis_cache)
        fix_pnl_sync(tracker, redis_cache)
        fixes_applied << :pnl
        @stats[:pnl_synced] += 1
      end

      # 4. Sync ActiveCache PnL from Redis
      sync_activecache_pnl(tracker, active_cache, redis_cache)

      return unless fixes_applied.any?

      @stats[:positions_fixed] += 1
      Rails.logger.info("[ReconciliationService] Fixed tracker #{tracker.id}: #{fixes_applied.join(', ')}")
    end

    def subscribed?(tracker, hub)
      return false unless hub.running?

      segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
      return false unless segment && tracker.security_id

      hub.subscribed?(segment: segment, security_id: tracker.security_id)
    end

    def fix_subscription(tracker, hub)
      return unless hub.running? || hub.respond_to?(:start!)

      hub.start! unless hub.running?
      tracker.subscribe
    end

    def in_active_cache?(tracker, active_cache)
      active_cache.get_by_tracker_id(tracker.id).present?
    end

    def fix_active_cache(tracker, active_cache)
      return unless tracker.entry_price&.positive?

      active_cache.add_position(tracker: tracker)
    end

    def pnl_needs_sync?(tracker, redis_cache)
      redis_pnl = redis_cache.fetch_pnl(tracker.id)
      return false unless redis_pnl && redis_pnl[:pnl]

      db_pnl = tracker.last_pnl_rupees.to_f
      redis_pnl_value = redis_pnl[:pnl].to_f

      # Sync if difference is significant (>1 rupee or >1%)
      (db_pnl - redis_pnl_value).abs > 1.0
    end

    def fix_pnl_sync(tracker, _redis_cache)
      tracker.hydrate_pnl_from_cache!
      tracker.reload
    end

    def sync_activecache_pnl(tracker, active_cache, _redis_cache = nil)
      position = active_cache.get_by_tracker_id(tracker.id)
      return unless position

      redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
      return unless redis_pnl && redis_pnl[:pnl]

      # Update ActiveCache with Redis PnL data using update_position method
      updates = {}
      updates[:pnl] = redis_pnl[:pnl].to_f if redis_pnl[:pnl]
      updates[:pnl_pct] = redis_pnl[:pnl_pct].to_f if redis_pnl[:pnl_pct]
      updates[:high_water_mark] = redis_pnl[:hwm_pnl].to_f if redis_pnl[:hwm_pnl]
      updates[:current_ltp] = redis_pnl[:ltp].to_f if redis_pnl[:ltp]&.to_f&.positive?

      # Update peak profit if available and higher than current
      if redis_pnl[:peak_profit_pct] && redis_pnl[:peak_profit_pct].to_f > (position.peak_profit_pct || 0)
        updates[:peak_profit_pct] = redis_pnl[:peak_profit_pct].to_f
      end

      active_cache.update_position(tracker.id, **updates) if updates.any?
    end
  end
end
