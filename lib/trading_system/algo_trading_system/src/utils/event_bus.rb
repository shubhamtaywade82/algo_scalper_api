# frozen_string_literal: true

require 'dry/events'

module Utils
  # Central event bus for inter-module communication
  class EventBus
    include Dry::Events::Publisher[:algo_trading_system]

    # Register known events
    register_event('market_data.candle_closed')
    register_event('market_data.tick')
    register_event('indicator.updated')
    register_event('order.placed')
    register_event('order.filled')

    class << self
      def instance
        @instance ||= new
      end

      def publish(event_id, payload = {})
        instance.publish(event_id, **payload)
      end

      def subscribe(event_id, &block)
        instance.subscribe(event_id, &block)
      end
    end
  end
end
