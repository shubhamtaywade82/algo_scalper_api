# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'

module Live
  class OrderUpdateHandler
    include Singleton

    FILL_STATUSES = %w[TRADED COMPLETE].freeze
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

    def process_update(payload)
      handle_update(payload)
    end

    def handle_order_update(payload)
      handle_update(payload)
    end

    def find_tracker_by_order_id(order_id)
      PositionTracker.find_by(order_no: order_id)
    end

    private

    def handle_update(payload)
      order_no = payload[:order_no] || payload[:order_id]
      return if order_no.blank?

      tracker = PositionTracker.find_by(order_no: order_no)
      return unless tracker

      status = payload[:order_status] || payload[:status]
      avg_price = safe_decimal(payload[:average_traded_price] || payload[:average_price])
      quantity = payload[:filled_quantity] || payload[:quantity]

      transaction_type = (payload[:transaction_type] || payload[:side] || payload[:transaction_side]).to_s.upcase

      if FILL_STATUSES.include?(status)
        if transaction_type == 'SELL'
          # Use avg_price from order update as exit_price
          tracker.mark_exited!(exit_price: avg_price)
        else
          tracker.mark_active!(avg_price: avg_price, quantity: quantity)
        end
      elsif CANCELLED_STATUSES.include?(status)
        tracker.mark_cancelled!
      end
    rescue StandardError => _e
      # Rails.logger.error("Failed to process Dhan order update: #{_e.class} - #{_e.message}")
    end

    def safe_decimal(value)
      return if value.nil?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
