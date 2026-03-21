# frozen_string_literal: true

module Positions
  class ActiveForExit
    def self.call
      PositionTracker.active.preload(:instrument, :watchable)
    end
  end
end
