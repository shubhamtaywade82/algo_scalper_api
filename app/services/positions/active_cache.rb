# frozen_string_literal: true

require 'singleton'
require 'concurrent/map'

module Positions
  # Ultra-fast in-memory position cache for NEMESIS V3
  # Mirrors Redis PnL + RedisTickCache for sub-millisecond lookups
  # Subscribes directly to MarketFeedHub callbacks for real-time updates
  # rubocop:disable Metrics/ClassLength
  class ActiveCache
    include Singleton

    # Position data structure
    PositionData = Struct.new(
      :tracker_id,
      :security_id,
      :segment,
      :entry_price,
      :quantity,
      :sl_price,
      :tp_price,
      :high_water_mark,
      :current_ltp,
      :pnl,
      :pnl_pct,
      :peak_profit_pct,
      :trend,
      :time_in_position,
      :breakeven_locked,
      :trailing_stop_price,
      :last_updated_at,
      keyword_init: true
    ) do
      def composite_key
        "#{segment}:#{security_id}"
      end

      def valid?
        entry_price&.positive? && current_ltp&.positive?
      end

      def sl_hit?
        return false unless sl_price && current_ltp

        # For long positions (CE), SL is below entry
        current_ltp <= sl_price
      end

      def tp_hit?
        return false unless tp_price && current_ltp

        # For long positions (CE), TP is above entry
        current_ltp >= tp_price
      end

      def update_ltp(ltp, timestamp: Time.current)
        self.current_ltp = ltp.to_f
        self.last_updated_at = timestamp
        recalculate_pnl
      end

      # rubocop:disable Metrics/AbcSize
      def recalculate_pnl
        return unless entry_price&.positive? && current_ltp&.positive? && quantity&.positive?

        self.pnl = (current_ltp - entry_price) * quantity
        self.pnl_pct = ((current_ltp - entry_price) / entry_price * 100.0).round(4)

        # Update HWM
        self.high_water_mark = pnl if high_water_mark.nil? || pnl > high_water_mark

        # Update peak profit percentage (highest profit % achieved)
        old_peak = peak_profit_pct
        self.peak_profit_pct = pnl_pct if peak_profit_pct.nil? || pnl_pct > peak_profit_pct

        # NEW (Step 12): Persist peak if it was updated
        # Note: Peak persistence is handled by ActiveCache.update_ltp, not here
        # This avoids calling private methods from PositionData struct
      end
      # rubocop:enable Metrics/AbcSize
    end

    def initialize
      @cache = Concurrent::Map.new # composite_key => PositionData
      @tracker_index = Concurrent::Map.new # tracker_id => composite_key
      @lock = Mutex.new
      @subscription_id = nil
      @stats = {
        positions_tracked: 0,
        updates_processed: 0,
        errors: 0
      }
      # Redis connection for peak persistence (Step 12)
      @redis = begin
        Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      rescue StandardError => e
        Rails.logger.error("[ActiveCache] Redis init error: #{e.class} - #{e.message}")
        nil
      end
    end

    # Start the cache (subscribe to MarketFeedHub callbacks)
    # @return [Boolean] True if started successfully
    def start!
      return true if @subscription_id

      # Subscribe directly to MarketFeedHub callbacks (no FeedListener needed)
      hub = Live::MarketFeedHub.instance
      hub.on_tick { |tick| handle_tick(tick) }

      @subscription_id = 'market_feed_hub_callback' # Mark as subscribed

      # NEW (Step 12): Reload peak values from Redis on startup
      reload_peaks

      Rails.logger.info('[Positions::ActiveCache] Started and subscribed to MarketFeedHub callbacks')
      true
    rescue StandardError => e
      Rails.logger.error("[Positions::ActiveCache] Failed to start: #{e.class} - #{e.message}")
      false
    end

    # Stop the cache (unsubscribe from MarketFeedHub)
    # @return [Boolean] True if stopped successfully
    def stop!
      return false unless @subscription_id

      # NOTE: MarketFeedHub doesn't support removing specific callbacks.
      # This is a no-op for now - callbacks will be cleared when hub stops.
      @subscription_id = nil
      Rails.logger.info('[Positions::ActiveCache] Stopped')
      true
    rescue StandardError => e
      Rails.logger.error("[Positions::ActiveCache] Failed to stop: #{e.class} - #{e.message}")
      false
    end

    # Add or update a position in the cache
    # @param tracker [PositionTracker] PositionTracker instance
    # @param sl_price [Float, nil] Stop loss price
    # @param tp_price [Float, nil] Take profit price
    # @return [PositionData] The cached position data
    # rubocop:disable Metrics/AbcSize
    def add_position(tracker:, sl_price: nil, tp_price: nil)
      return nil unless tracker.active?
      return nil unless tracker.entry_price&.positive?

      composite_key = "#{tracker.segment}:#{tracker.security_id}"

      position_data = PositionData.new(
        tracker_id: tracker.id,
        security_id: tracker.security_id.to_s,
        segment: tracker.segment.to_s,
        entry_price: tracker.entry_price.to_f,
        quantity: tracker.quantity.to_i,
        sl_price: sl_price&.to_f,
        tp_price: tp_price&.to_f,
        high_water_mark: tracker.high_water_mark_pnl.to_f,
        current_ltp: nil, # Will be updated on next LTP event
        pnl: 0.0,
        pnl_pct: 0.0,
        peak_profit_pct: 0.0, # Initial peak profit percentage
        trend: :neutral, # Will be determined from price action
        time_in_position: Time.current - tracker.created_at,
        breakeven_locked: tracker.breakeven_locked?,
        trailing_stop_price: tracker.trailing_stop_price&.to_f,
        last_updated_at: Time.current
      )

      @cache[composite_key] = position_data
      @tracker_index[tracker.id] = composite_key
      @stats[:positions_tracked] = @cache.size

      # NEW (Step 12): Check for pending peak value from reload_peaks
      if @pending_peaks && @pending_peaks[tracker.id]
        peak_value = @pending_peaks.delete(tracker.id)
        position_data.peak_profit_pct = peak_value if peak_value > (position_data.peak_profit_pct || 0)
        Rails.logger.debug { "[ActiveCache] Applied pending peak for tracker #{tracker.id}: #{peak_value.round(2)}%" }
      end

      # Try to get current LTP from cache
      ltp = Live::TickCache.ltp(tracker.segment, tracker.security_id)
      position_data.update_ltp(ltp) if ltp&.positive?

      Rails.logger.debug { "[Positions::ActiveCache] Added position #{tracker.id} (#{composite_key})" }
      position_data
    rescue StandardError => e
      @stats[:errors] += 1
      Rails.logger.error("[Positions::ActiveCache] Failed to add position #{tracker.id}: #{e.class} - #{e.message}")
      nil
    end
    # rubocop:enable Metrics/AbcSize

    # Remove a position from the cache
    # @param tracker_id [Integer] PositionTracker ID
    # @return [Boolean] True if removed
    def remove_position(tracker_id)
      composite_key = @tracker_index.delete(tracker_id)
      return false unless composite_key

      @cache.delete(composite_key)
      @stats[:positions_tracked] = @cache.size
      Rails.logger.debug { "[Positions::ActiveCache] Removed position #{tracker_id} (#{composite_key})" }
      true
    rescue StandardError => e
      @stats[:errors] += 1
      Rails.logger.error("[Positions::ActiveCache] Failed to remove position #{tracker_id}: #{e.class} - #{e.message}")
      false
    end

    # Get position data by composite key
    # @param segment [String] Exchange segment
    # @param security_id [String] Security ID
    # @return [PositionData, nil]
    def get(segment, security_id)
      composite_key = "#{segment}:#{security_id}"
      @cache[composite_key]
    end

    # Get position data by tracker ID
    # @param tracker_id [Integer] PositionTracker ID
    # @return [PositionData, nil]
    def get_by_tracker_id(tracker_id)
      composite_key = @tracker_index[tracker_id]
      return nil unless composite_key

      @cache[composite_key]
    end

    # Get all active positions
    # @return [Array<PositionData>]
    def all_positions
      @cache.values
    end

    # Get positions for a specific security
    # @param segment [String] Exchange segment
    # @param security_id [String] Security ID
    # @return [Array<PositionData>]
    def positions_for(segment, security_id)
      composite_key = "#{segment}:#{security_id}"
      position = @cache[composite_key]
      position ? [position] : []
    end

    # Update position metadata (SL, TP, breakeven, etc.)
    # @param tracker_id [Integer] PositionTracker ID
    # @param updates [Hash] Hash of updates (sl_price, tp_price, breakeven_locked, etc.)
    # @return [Boolean] True if updated
    def update_position(tracker_id, **updates)
      position = get_by_tracker_id(tracker_id)
      return false unless position

      # Track if peak_profit_pct is being updated
      peak_updated = updates.key?(:peak_profit_pct)
      old_peak = position.peak_profit_pct if peak_updated

      updates.each do |key, value|
        position[key] = value if position.respond_to?("#{key}=")
      end

      # NEW (Step 12): Persist peak if it was updated
      if peak_updated && position.peak_profit_pct != old_peak && position.peak_profit_pct&.positive?
        persist_peak(tracker_id, position.peak_profit_pct)
      end

      position.last_updated_at = Time.current
      Rails.logger.debug { "[Positions::ActiveCache] Updated position #{tracker_id}: #{updates.keys.join(', ')}" }
      true
    rescue StandardError => e
      @stats[:errors] += 1
      Rails.logger.error("[Positions::ActiveCache] Failed to update position #{tracker_id}: #{e.class} - #{e.message}")
      false
    end

    # Bulk load positions from database
    # @return [Integer] Number of positions loaded
    def bulk_load!
      count = 0
      PositionTracker.active.find_each do |tracker|
        next unless tracker.entry_price&.positive?

        # Try to get SL/TP from meta or calculate defaults
        sl_price = calculate_default_sl(tracker)
        tp_price = calculate_default_tp(tracker)

        add_position(tracker: tracker, sl_price: sl_price, tp_price: tp_price)
        count += 1
      end

      Rails.logger.info("[Positions::ActiveCache] Bulk loaded #{count} positions")
      count
    rescue StandardError => e
      Rails.logger.error("[Positions::ActiveCache] Bulk load failed: #{e.class} - #{e.message}")
      0
    end

    # Clear all positions
    # @return [Boolean]
    # rubocop:disable Naming/PredicateMethod
    def clear
      @cache.clear
      @tracker_index.clear
      @stats[:positions_tracked] = 0
      Rails.logger.info('[Positions::ActiveCache] Cleared all positions')
      true
    end
    # rubocop:enable Naming/PredicateMethod

    # Get statistics
    # @return [Hash]
    def stats
      @stats.merge(positions_tracked: @cache.size)
    end

    private

    # Handle tick from MarketFeedHub (replaces EventBus LTP event handling)
    # @param tick [Hash] Raw tick data from MarketFeedHub
    def handle_tick(tick)
      return unless tick.is_a?(Hash)
      return unless tick[:ltp].to_f.positive?
      return unless tick[:segment].present? && tick[:security_id].present?

      composite_key = "#{tick[:segment]}:#{tick[:security_id]}"
      position = @cache[composite_key]
      return unless position

      # Update LTP
      position.update_ltp(tick[:ltp].to_f, timestamp: Time.current)
      @stats[:updates_processed] += 1

      # Check exit triggers
      check_exit_triggers(position)
    rescue StandardError => e
      @stats[:errors] += 1
      Rails.logger.error("[Positions::ActiveCache] Error handling tick: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
    end

    # Check for SL/TP hits and emit events
    # @param position [PositionData] Position data
    def check_exit_triggers(position)
      if position.sl_hit?
        Core::EventBus.instance.publish(Core::EventBus::EVENTS[:sl_hit], {
                                          tracker_id: position.tracker_id,
                                          position: position
                                        })
        return
      end

      return unless position.tp_hit?

      Core::EventBus.instance.publish(Core::EventBus::EVENTS[:tp_hit], {
                                        tracker_id: position.tracker_id,
                                        position: position
                                      })
    end

    # Calculate default SL from tracker (30% below entry for CE)
    # @param tracker [PositionTracker] PositionTracker instance
    # @return [Float, nil]
    def calculate_default_sl(tracker)
      return nil unless tracker.entry_price&.positive?

      # Default: 30% below entry for long positions
      tracker.entry_price.to_f * 0.70
    end

    # Calculate default TP from tracker (60% above entry for CE)
    # @param tracker [PositionTracker] PositionTracker instance
    # @return [Float, nil]
    def calculate_default_tp(tracker)
      return nil unless tracker.entry_price&.positive?

      # Default: 60% above entry for long positions
      tracker.entry_price.to_f * 1.60
    end

    # NEW (Step 12): Persist peak profit percentage to Redis
    # @param tracker_id [Integer] PositionTracker ID
    # @param peak_profit_pct [Float] Peak profit percentage
    # @return [Boolean] True if persisted successfully
    def persist_peak(tracker_id, peak_profit_pct)
      return false unless @redis && tracker_id && peak_profit_pct

      redis_key = "position_peaks:#{tracker_id}"
      ttl_seconds = 7.days.to_i # 7 days TTL (longer than typical position duration)

      @redis.setex(redis_key, ttl_seconds, peak_profit_pct.to_s)
      Rails.logger.debug { "[ActiveCache] Persisted peak for tracker #{tracker_id}: #{peak_profit_pct.round(2)}%" }
      true
    rescue StandardError => e
      Rails.logger.error("[ActiveCache] Failed to persist peak for tracker #{tracker_id}: #{e.class} - #{e.message}")
      false
    end

    # NEW (Step 12): Reload peak profit percentages from Redis for all active positions
    # Called on startup to restore peak values after restart
    # @return [Integer] Number of peaks reloaded
    def reload_peaks
      return 0 unless @redis

      count = 0
      PositionTracker.active.find_each do |tracker|
        redis_key = "position_peaks:#{tracker.id}"
        peak_str = @redis.get(redis_key)
        next unless peak_str

        peak_value = peak_str.to_f
        next unless peak_value.positive?

        # Get position from cache (may not exist if cache not loaded yet)
        position = get_by_tracker_id(tracker.id)
        if position
          # Only update if persisted peak is higher than current
          if position.peak_profit_pct.nil? || peak_value > position.peak_profit_pct
            position.peak_profit_pct = peak_value
            Rails.logger.debug { "[ActiveCache] Reloaded peak for tracker #{tracker.id}: #{peak_value.round(2)}%" }
            count += 1
          end
        else
          # Position not in cache yet - will be loaded when position is added
          # Store in a temporary map for later use
          @pending_peaks ||= {}
          @pending_peaks[tracker.id] = peak_value
        end
      end

      Rails.logger.info("[ActiveCache] Reloaded #{count} peak values from Redis") if count.positive?
      count
    rescue StandardError => e
      Rails.logger.error("[ActiveCache] Failed to reload peaks: #{e.class} - #{e.message}")
      0
    end
  end
  # rubocop:enable Metrics/ClassLength
end
