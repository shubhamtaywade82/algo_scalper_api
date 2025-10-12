# frozen_string_literal: true

module Live
  class TickCache
    def self.put(tick)
      ::TickCache.instance.put(tick)
    end

    def self.get(segment, security_id)
      ::TickCache.instance.fetch(segment, security_id)
    end

    def self.ltp(segment, security_id)
      ::TickCache.instance.ltp(segment, security_id)
    end

    def self.all
      ::TickCache.instance.all
    end
  end
end
