# frozen_string_literal: true

require "singleton"

module Live
  class OrderUpdateHandler
    include Singleton

    FILL_STATUSES = %w[TRADED COMPLETE PARTIAL_FILL].freeze
    CANCELLED_STATUSES = %w[CANCELLED REJECTED].freeze

    def initialize
      @subscribed = false
      @lock = Mutex.new
    end

    def start!
      return if @subscribed

      @lock.synchronize do
        return if @subscribed

        Live::OrderUpdateHub.instance.start!
        Live::OrderUpdateHub.instance.on_update { |payload| handle_update(payload) }
        @subscribed = true
      end
    end

    def stop!
      @lock.synchronize { @subscribed = false }
    end

    private

    def handle_update(payload)
      order = BrokerOrder.upsert_from_payload(payload)
      return unless order

      tracker = PositionTracker.find_by(order_no: order.order_no)
      return unless tracker

      status = order.status.to_s.upcase
      avg_price = order.avg_traded_price
      quantity = order.traded_quantity || order.quantity || tracker.quantity

      if FILL_STATUSES.include?(status)
        tracker.mark_active!(avg_price: avg_price, quantity: quantity)
      elsif CANCELLED_STATUSES.include?(status)
        tracker.mark_cancelled!
      end
    rescue StandardError => e
      Rails.logger.error("Failed to process Dhan order update: #{e.class} - #{e.message}")
    end

  end
end
