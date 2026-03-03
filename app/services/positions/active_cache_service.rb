# frozen_string_literal: true

# Service adapter for ActiveCache to integrate with TradingSystem::Supervisor
module Positions
  class ActiveCacheService
    def initialize
      @cache = Positions::ActiveCache.instance
    end

    def start
      @cache.start!
    end

    def stop
      @cache.stop!
    end
  end
end
