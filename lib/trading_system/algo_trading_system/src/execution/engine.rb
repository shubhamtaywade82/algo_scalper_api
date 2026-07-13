# frozen_string_literal: true

require_relative 'risk_engine'
require_relative 'order_manager'
require_relative 'position_tracker'

module Execution
  # Wires Execution Engine to Event Bus
  class Engine
    attr_reader :position_tracker, :risk_engine, :order_manager

    def initialize(api_client, event_bus: Utils::EventBus)
      @event_bus = event_bus
      @position_tracker = PositionTracker.new
      @risk_engine = RiskEngine.new(@position_tracker)
      @order_manager = OrderManager.new(api_client, @risk_engine, event_bus: @event_bus)

      subscribe_events
    end

    private

    def subscribe_events
      @event_bus.subscribe('order.filled') do |payload|
        @position_tracker.on_order_filled(payload[:order])
      end

      @event_bus.subscribe('market_data.tick') do |payload|
        @position_tracker.on_tick(payload[:tick])
      end

      @event_bus.subscribe('market_data.candle_closed') do |payload|
        @position_tracker.on_candle(payload[:candle])
      end
    end
  end
end
