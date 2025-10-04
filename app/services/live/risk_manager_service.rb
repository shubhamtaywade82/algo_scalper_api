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
      positions = refresh_positions_indexed

      PositionTracker.active.find_each do |tracker|
        position_entry = positions[tracker.security_id.to_s]
        position = select_position_entry(position_entry, tracker)
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

    def refresh_positions_indexed
      Live::PositionStore.instance.refresh_and_index
    end

    def fetch_pnl(position, tracker)
      return BigDecimal(position.pnl.to_s) if position.respond_to?(:pnl) && position.pnl

      if position.is_a?(Hash)
        unrealized = position[:unrealized_profit] || position[:unrealized_profit_rupees]
        return BigDecimal(unrealized.to_s) if unrealized
      end

      quantity = extract_quantity(position) || tracker.quantity
      avg_price = extract_average_price(position) || tracker.entry_price
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

    def extract_quantity(position)
      if position.respond_to?(:quantity)
        position.quantity
      elsif position.is_a?(Hash)
        position[:quantity] || position[:net_qty]
      end
    end

    def extract_average_price(position)
      if position.respond_to?(:average_price)
        position.average_price
      elsif position.is_a?(Hash)
        position[:average_price] || position[:buy_avg] || position[:cost_price]
      end
    end

    def select_position_entry(entry, tracker)
      return if entry.blank?

      return entry unless entry.is_a?(Array)

      match = entry.find { |pos| pos[:order_no].present? && pos[:order_no] == tracker.order_no }
      match || entry.first
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
