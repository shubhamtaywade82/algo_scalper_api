# frozen_string_literal: true

module Live
  # Adapter to make Live::MarketFeedHub compatible with TradingSystem::Supervisor.
  # The hub exposes start!/stop!, while the supervisor expects start/stop.
  class MarketFeedHubService
    def initialize(hub: Live::MarketFeedHub.instance)
      @hub = hub
    end

    def start
      @hub.start!
    end

    def stop
      @hub.stop!
    end

    delegate :subscribe_many, to: :@hub
  end
end

