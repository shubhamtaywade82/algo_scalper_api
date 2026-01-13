# frozen_string_literal: true

module Live
  class PositionTrackerPruner
    def self.call
      # Use cached active positions to avoid redundant query
      ids = Positions::ActivePositionsCache.instance.active_tracker_ids.map(&:to_s)
      Live::RedisPnlCache.instance.prune_except(ids)
      Live::RedisTickCache.instance.prune_stale
    end
  end
end
