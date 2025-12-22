# frozen_string_literal: true

module Positions
  # Shared cache for active PositionTracker records
  # Reduces redundant database queries across multiple services
  class ActivePositionsCache
    include Singleton

    CACHE_TTL = 5.seconds
    CACHE_TTL_MARKET_CLOSED = 60.seconds # Longer TTL when market is closed and no positions

    def initialize
      @cached_trackers = nil
      @cached_at = nil
      @lock = Mutex.new
    end

    # Get cached active trackers, refresh if stale
    # @return [Array<PositionTracker>] Array of active PositionTracker records
    def active_trackers
      @lock.synchronize do
        return @cached_trackers if cached?

        # Refresh without nested lock (we're already synchronized)
        @cached_trackers = PositionTracker.active.includes(:instrument).to_a
        @cached_at = Time.current
        Rails.logger.debug { "[ActivePositionsCache] Refreshed cache: #{@cached_trackers.size} active positions" }
        @cached_trackers
      end
    end

    # Get active tracker IDs only (lighter query)
    # @return [Array<Integer>] Array of active tracker IDs
    def active_tracker_ids
      active_trackers.map(&:id)
    end

    # Get cached count without refreshing (for market-closed checks)
    # Returns nil if cache doesn't exist, otherwise returns count
    # @return [Integer, nil] Count of active trackers from cache, or nil if not cached
    def cached_count
      @lock.synchronize do
        return nil unless @cached_trackers

        @cached_trackers.size
      end
    end

    # Force refresh cache
    def refresh!
      @lock.synchronize do
        @cached_trackers = PositionTracker.active.includes(:instrument).to_a
        @cached_at = Time.current
        Rails.logger.debug { "[ActivePositionsCache] Refreshed cache: #{@cached_trackers.size} active positions" }
      end
    end

    # Clear cache (force next call to refresh)
    def clear!
      @lock.synchronize do
        @cached_trackers = nil
        @cached_at = nil
      end
    end

    # Check if cache is still valid
    def cached?
      return false unless @cached_at && @cached_trackers

      # Use longer TTL if market is closed and there are no positions
      ttl = if TradingSession::Service.market_closed? && @cached_trackers.size.zero?
              CACHE_TTL_MARKET_CLOSED
            else
              CACHE_TTL
            end

      (Time.current - @cached_at) < ttl
    end

    # Get cache stats
    def stats
      {
        cached: cached?,
        cached_at: @cached_at,
        count: @cached_trackers&.size || 0,
        age_seconds: @cached_at ? (Time.current - @cached_at).round(2) : nil
      }
    end
  end
end
