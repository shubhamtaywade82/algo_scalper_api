# frozen_string_literal: true

require "singleton"

module Live
  class OrderUpdateHandler
    include Singleton

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
      Positions::Manager.instance.handle_order_update(payload)
    rescue StandardError => e
      Rails.logger.error("Failed to process Dhan order update: #{e.class} - #{e.message}")
    end

  end
end
