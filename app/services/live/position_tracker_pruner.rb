# frozen_string_literal: true

module Live
  class PositionTrackerPruner
    def self.call
      ids = PositionTracker.active.ids.map(&:to_s)
      Live::RedisPnlCache.instance.prune_except(ids)
      Live::RedisTickCache.instance.prune_stale
    end
  end
end
