# frozen_string_literal: true

require 'singleton'

module Live
  class RedisPnlCache
    include Singleton

    REDIS_KEY_PREFIX = 'pnl:tracker'
    TTL_SECONDS = 6.hours.to_i
    SYNC_THROTTLE_SECONDS = 30 # Only sync to DB every 30 seconds per tracker

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      @sync_timestamps = {} # tracker_id => last_sync_time (in-memory cache)
      @sync_mutex = Mutex.new
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] init error: #{e.message}") if defined?(Rails)
      @redis = nil
    end

    # store only computed PnL (strings stored to Redis)
    # @param tracker [PositionTracker, nil] Optional tracker instance for additional metadata
    def store_pnl(tracker_id:, pnl:, ltp:, hwm:, pnl_pct: nil, hwm_pnl_pct: nil, timestamp: Time.current, tracker: nil)
      return false unless @redis

      key = pnl_key(tracker_id)
      data = {
        'pnl' => pnl.to_f.to_s,
        'pnl_pct' => pnl_pct&.to_f.to_s,
        'ltp' => ltp.to_f.to_s,
        'hwm_pnl' => hwm.to_f.to_s,
        'hwm_pnl_pct' => hwm_pnl_pct&.to_f.to_s,
        'timestamp' => timestamp.to_i.to_s,
        'updated_at' => Time.current.to_i.to_s
      }

      # Sync PnL to database (throttled - only every 30 seconds per tracker)
      sync_pnl_to_database_throttled(tracker_id, pnl, pnl_pct, hwm, hwm_pnl_pct) if tracker_id

      # Add additional metadata if tracker is provided
      if tracker
        # Direct fields from PositionTracker
        data['entry_price'] = tracker.entry_price&.to_f.to_s if tracker.entry_price.present?
        data['quantity'] = tracker.quantity.to_i.to_s if tracker.quantity.present?
        data['segment'] = tracker.segment.to_s if tracker.segment.present?
        data['security_id'] = tracker.security_id.to_s if tracker.security_id.present?
        data['symbol'] = tracker.symbol.to_s if tracker.symbol.present?
        data['side'] = tracker.side.to_s if tracker.side.present?
        data['order_no'] = tracker.order_no.to_s if tracker.order_no.present?
        data['paper'] = (tracker.paper? ? '1' : '0')
        data['entry_timestamp'] = tracker.created_at.to_i.to_s if tracker.created_at.present?

        # Calculated fields
        if tracker.entry_price.present? && ltp.to_f.positive?
          price_change = ((ltp.to_f - tracker.entry_price.to_f) / tracker.entry_price.to_f * 100.0)
          data['price_change_pct'] = price_change.round(4).to_s
        end

        if tracker.entry_price.present? && tracker.quantity.present?
          capital_deployed = tracker.entry_price.to_f * tracker.quantity.to_i
          data['capital_deployed'] = capital_deployed.round(2).to_s
        end

        if tracker.created_at.present?
          time_in_position = Time.current.to_i - tracker.created_at.to_i
          data['time_in_position_sec'] = time_in_position.to_s
        end

        # Drawdown calculations
        if hwm.to_f.positive?
          drawdown_rupees = hwm.to_f - pnl.to_f
          data['drawdown_rupees'] = drawdown_rupees.round(2).to_s
          drawdown_pct = (drawdown_rupees / hwm.to_f * 100.0)
          data['drawdown_pct'] = drawdown_pct.round(4).to_s
        end

        # Resolved metadata via MetadataResolver
        begin
          index_key = Positions::MetadataResolver.index_key(tracker)
          data['index_key'] = index_key.to_s if index_key.present?
        rescue StandardError
          nil
        end

        begin
          direction = Positions::MetadataResolver.direction(tracker)
          data['direction'] = direction.to_s if direction.present?
        rescue StandardError
          nil
        end
      end

      @redis.hset(key, **data)
      # ensure TTL
      ttl = @redis.ttl(key).to_i
      @redis.expire(key, TTL_SECONDS) if ttl < (TTL_SECONDS / 2)
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] store_pnl error: #{e.message}") if defined?(Rails)
      false
    end

    def fetch_pnl(tracker_id)
      return nil unless @redis

      key = pnl_key(tracker_id)
      raw = @redis.hgetall(key)
      return nil if raw.nil? || raw.empty?

      {
        pnl: raw['pnl']&.to_f,
        pnl_pct: raw['pnl_pct']&.to_f,
        ltp: raw['ltp']&.to_f,
        hwm_pnl: raw['hwm_pnl']&.to_f,
        hwm_pnl_pct: raw['hwm_pnl_pct']&.to_f,
        timestamp: raw['timestamp']&.to_i,
        updated_at: raw['updated_at']&.to_i,
        # Additional metadata (may be nil if not stored)
        entry_price: raw['entry_price']&.to_f,
        quantity: raw['quantity']&.to_i,
        segment: raw['segment'],
        security_id: raw['security_id'],
        symbol: raw['symbol'],
        side: raw['side'],
        order_no: raw['order_no'],
        paper: raw['paper'] == '1',
        entry_timestamp: raw['entry_timestamp']&.to_i,
        price_change_pct: raw['price_change_pct']&.to_f,
        capital_deployed: raw['capital_deployed']&.to_f,
        time_in_position_sec: raw['time_in_position_sec']&.to_i,
        drawdown_rupees: raw['drawdown_rupees']&.to_f,
        drawdown_pct: raw['drawdown_pct']&.to_f,
        index_key: raw['index_key'],
        direction: raw['direction']&.to_sym
      }
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] fetch_pnl error: #{e.message}") if defined?(Rails)
      nil
    end

    # clear all pnl:* keys (dangerous but useful for tests/dev)
    def clear
      return false unless @redis

      pattern = "#{REDIS_KEY_PREFIX}:*"
      @redis.scan_each(match: pattern) { |k| @redis.del(k) }
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] clear error: #{e.message}") if defined?(Rails)
      false
    end

    # Sync PnL from Redis to PositionTracker database (throttled)
    # Only syncs every SYNC_THROTTLE_SECONDS (30s) per tracker to reduce DB hits
    def sync_pnl_to_database_throttled(tracker_id, pnl, pnl_pct, hwm, hwm_pnl_pct = nil)
      return unless tracker_id

      @sync_mutex.synchronize do
        last_sync = @sync_timestamps[tracker_id]
        now = Time.current

        # Skip if synced recently (within throttle window)
        return if last_sync && (now - last_sync) < SYNC_THROTTLE_SECONDS

        # Update timestamp
        @sync_timestamps[tracker_id] = now
      end

      # Perform actual sync
      sync_pnl_to_database(tracker_id, pnl, pnl_pct, hwm, hwm_pnl_pct)
    end

    # Force sync PnL from Redis to PositionTracker database (no throttling)
    # Use this when you need immediate DB sync (e.g., on exit)
    def sync_pnl_to_database(tracker_id, pnl, pnl_pct, hwm, hwm_pnl_pct = nil)
      return unless tracker_id

      begin
        tracker = PositionTracker.find_by(id: tracker_id)
        return unless tracker&.active?

        # Update DB with Redis PnL data
        attrs = {
          last_pnl_rupees: BigDecimal(pnl.to_s),
          last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil,
          high_water_mark_pnl: hwm ? BigDecimal(hwm.to_s) : tracker.high_water_mark_pnl
        }

        # Store hwm_pnl_pct in meta if provided
        if hwm_pnl_pct
          meta = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}
          meta['hwm_pnl_pct'] = hwm_pnl_pct.to_f
          attrs[:meta] = meta
        end

        tracker.update!(attrs)

        # Update sync timestamp
        @sync_mutex.synchronize do
          @sync_timestamps[tracker_id] = Time.current
        end
      rescue ActiveRecord::RecordNotFound
        # Tracker doesn't exist, skip
        nil
      rescue StandardError => e
        Rails.logger.error("[RedisPnL] sync_pnl_to_database failed for tracker #{tracker_id}: #{e.class} - #{e.message}")
      end
    end

    def clear_tracker(tracker_id)
      return false unless @redis

      @redis.del(pnl_key(tracker_id))
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] clear_tracker error: #{e.message}") if defined?(Rails)
      false
    end

    # fetch everything: returns hash tracker_id => data
    def fetch_all
      return {} unless @redis

      out = {}
      pattern = "#{REDIS_KEY_PREFIX}:*"
      @redis.scan_each(match: pattern) do |key|
        id = key.split(':').last
        out[id.to_i] = fetch_pnl(id)
      end
      out
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] fetch_all error: #{e.message}") if defined?(Rails)
      {}
    end

    def health_check
      return { status: :error, message: 'redis not init' } unless @redis

      @redis.ping
      { status: :ok, message: 'ok' }
    rescue StandardError => e
      { status: :error, message: e.message }
    end

    def each_tracker_key(&)
      pattern = "#{REDIS_KEY_PREFIX}:*"
      @redis.scan_each(match: pattern) do |key|
        tracker_id = key.split(':').last
        yield(key, tracker_id.to_s)
      end
    end

    def purge_exited!
      return false unless @redis

      # Use cached active positions to avoid redundant query
      active_ids = Positions::ActivePositionsCache.instance.active_tracker_ids.map(&:to_s).to_set

      deleted_count = 0
      pattern = 'pnl:tracker:*'
      @redis.scan_each(match: pattern) do |key|
        tracker_id = key.split(':').last
        unless active_ids.include?(tracker_id)
          @redis.del(key)
          deleted_count += 1
        end
      end

      Rails.logger.info("[RedisPnlCache] Purged #{deleted_count} exited position PnL entries") if deleted_count.positive?
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnlCache] purge_exited! error: #{e.message}")
      false
    end

    # Remove all pnl/tick entries except those for the given tracker IDs
    def prune_except(allowed_ids)
      allowed_set = allowed_ids.map(&:to_s).to_set

      # PnL cache keys
      each_tracker_key do |_key, tracker_id|
        unless allowed_set.include?(tracker_id.to_s)
          Rails.logger.warn("[RedisPnlCache] Pruning orphaned tracker_id=#{tracker_id}")
          clear_tracker(tracker_id)
        end
      end

      true
    end

    private

    def pnl_key(id)
      "#{REDIS_KEY_PREFIX}:#{id}"
    end
  end
end
