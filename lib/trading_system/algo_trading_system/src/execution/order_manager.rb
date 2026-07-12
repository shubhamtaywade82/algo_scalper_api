# frozen_string_literal: true

require_relative 'order'
require_relative '../utils/logger'

module Execution
  # Order lifecycle management
  class OrderManager
    def initialize(api_client, risk_engine, event_bus: Utils::EventBus)
      @api_client = api_client
      @risk_engine = risk_engine
      @event_bus = event_bus
      @orders = {}
    end

    def place_order(order_params, current_time: Time.now)
      order = Order.new(**order_params.merge(status: 'PENDING'))
      
      begin
        @risk_engine.validate!(order, current_time: current_time)
      rescue RiskEngine::RiskViolation => e
        Utils::Logger.warn("order.rejected", reason: e.message, symbol: order.symbol)
        order.status = 'REJECTED'
        return order
      end

      # Submit to broker
      payload = {
        transactionType: order.transaction_type,
        exchangeSegment: order.exchange || "NSE_FNO",
        productType: order.product_type || "INTRADAY",
        orderType: order.order_type,
        tradingSymbol: order.symbol,
        securityId: "TBD",
        quantity: order.quantity,
        price: order.price || 0.0,
        triggerPrice: order.trigger_price || 0.0
      }

      begin
        response = @api_client.place_order(payload)
        order.order_id = response[:orderId] || "mock_#{Time.now.to_i}"
        order.status = 'OPEN'
        @orders[order.order_id] = order
        @event_bus.publish('order.placed', order: order)
        Utils::Logger.info("order.placed", order_id: order.order_id, symbol: order.symbol)
      rescue StandardError => e
        order.status = 'FAILED'
        Utils::Logger.error("order.failed", error: e.message)
      end

      order
    end

    def cancel_order(order_id)
      order = @orders[order_id]
      return false unless order && %w[PENDING OPEN].include?(order.status)

      begin
        @api_client.cancel_order(order_id)
        order.status = 'CANCELLED'
        true
      rescue StandardError => e
        Utils::Logger.error("order.cancel_failed", error: e.message)
        false
      end
    end

    # TODO: Extract workflow method
def simulate_fill(order_id, price, time)
      order = @orders[order_id]
      return unless order && order.status == 'OPEN'

      order.status = 'FILLED'
      order.filled_price = price
      order.filled_at = time
      @event_bus.publish('order.filled', order: order)
    end
  end
end
