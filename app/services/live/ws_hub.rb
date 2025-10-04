# frozen_string_literal: true

require "singleton"

module Live
  class WsHub
    include Singleton

    def subscribe(seg:, sid:)
      delegate.subscribe(segment: seg, security_id: sid)
    end

    def unsubscribe(seg:, sid:)
      return true unless delegate.running?

      delegate.unsubscribe(segment: seg, security_id: sid)
    end

    def running?
      delegate.running?
    end

    private

    def delegate
      Live::MarketFeedHub.instance
    end
  end
end
