# frozen_string_literal: true

require "bigdecimal"
require "singleton"

module Live
  class RiskManagerService
    include Singleton

    LOOP_INTERVAL = 5
    MIN_PROFIT_LOCK = BigDecimal("1000")
    EXIT_DROP_PCT = BigDecimal("0.05")

    def initialize
      @mutex = Mutex.new
      @running = false
      @thread = nil
    end

    def start!
      return if @running

      @mutex.synchronize do
        return if @running

        @running = true
        @thread = Thread.new { monitor_loop }
        @thread.name = "risk-manager-service"
      end
    end

    def stop!
      @mutex.synchronize do
        @running = false
        @thread&.wakeup
        @thread = nil
      end
    end

    def running?
      @running
    end

    private

    def monitor_loop
      while running?
        enforce_trailing_stops
        sleep LOOP_INTERVAL
      end
    rescue StandardError => e
      Rails.logger.error("RiskManagerService crashed: #{e.class} - #{e.message}")
      @running = false
    end

    def enforce_trailing_stops
      positions = fetch_positions_indexed

      PositionTracker.active.find_each do |tracker|
        position = positions[tracker.security_id.to_s]
        next unless position

        pnl = fetch_pnl(position, tracker)
        next unless pnl

        tracker.with_lock do
          tracker.update_pnl!(pnl)

          if tracker.ready_to_trail?(pnl, MIN_PROFIT_LOCK) && tracker.trailing_stop_triggered?(pnl, EXIT_DROP_PCT)
            execute_exit(position, tracker)
          end
        end
      end
    end

    def fetch_positions_indexed
      Dhanhq.client.active_positions.each_with_object({}) do |position, map|
        security_id = position.respond_to?(:security_id) ? position.security_id : position[:security_id]
        map[security_id.to_s] = position if security_id
      end
    rescue StandardError => e
      Rails.logger.error("Failed to load active positions: #{e.class} - #{e.message}")
      {}
    end

    def fetch_pnl(position, tracker)
      return BigDecimal(position.pnl.to_s) if position.respond_to?(:pnl) && position.pnl

      quantity = (position.respond_to?(:quantity) ? position.quantity : position[:quantity]) || tracker.quantity
      avg_price = (position.respond_to?(:average_price) ? position.average_price : position[:average_price]) || tracker.entry_price
      ltp = fetch_ltp(position, tracker)
      return if quantity.nil? || avg_price.nil? || ltp.nil?

      (ltp - BigDecimal(avg_price.to_s)) * quantity.to_i
    rescue StandardError => e
      Rails.logger.error("Failed to compute PnL for tracker #{tracker.id}: #{e.class} - #{e.message}")
      nil
    end

    def fetch_ltp(position, tracker)
      segment =
        if position.respond_to?(:exchange_segment)
          position.exchange_segment
        else
          position[:exchange_segment]
        end

      ltp = Live::TickCache.ltp(segment || tracker.instrument.exchange_segment, tracker.security_id)
      ltp ? BigDecimal(ltp.to_s) : nil
    end

    def execute_exit(position, tracker)
      Rails.logger.info("Triggering trailing-stop exit for #{tracker.order_no} (PnL=#{tracker.last_pnl_rupees}).")
      exit_position(position)
      tracker.unsubscribe
      tracker.mark_exited!
    rescue StandardError => e
      Rails.logger.error("Failed to exit position #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def exit_position(position)
      if position.respond_to?(:exit!)
        position.exit!
      elsif position.respond_to?(:order_id)
        Dhanhq.client.cancel_order(order_id: position.order_id)
      end
    end
  end
end
