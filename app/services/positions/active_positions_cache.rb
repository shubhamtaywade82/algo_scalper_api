# frozen_string_literal: true

module Positions
  # Shared cache for active PositionTracker records
  # Reduces redundant database queries across multiple services
  class ActivePositionsCache
    include Singleton

    CACHE_TTL = 5.seconds

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
      @cached_at && @cached_trackers && (Time.current - @cached_at) < CACHE_TTL
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
