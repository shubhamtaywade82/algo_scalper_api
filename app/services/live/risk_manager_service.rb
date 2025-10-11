# frozen_string_literal: true

require "bigdecimal"
require "singleton"

module Live
  class RiskManagerService
    include Singleton

    LOOP_INTERVAL = 5

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
        enforce_daily_circuit_breaker
        sleep LOOP_INTERVAL
      end
    rescue StandardError => e
      Rails.logger.error("RiskManagerService crashed: #{e.class} - #{e.message}")
      @running = false
    end

    def enforce_trailing_stops
      positions = fetch_positions_indexed
      risk = risk_config

      PositionTracker.active.includes(:instrument).find_each do |tracker|
        position = positions[tracker.security_id.to_s]
        ltp = current_ltp(tracker, position)
        next unless ltp

        pnl = compute_pnl(tracker, position, ltp)
        next unless pnl

        pnl_pct = compute_pnl_pct(tracker, ltp)

        tracker.with_lock do
          tracker.update_pnl!(pnl, pnl_pct: pnl_pct)

          if should_lock_breakeven?(tracker, pnl_pct, risk[:breakeven_after_gain])
            tracker.lock_breakeven!
          end

          min_profit = tracker.min_profit_lock(risk[:trail_step_pct] || 0)
          drop_pct = BigDecimal((risk[:exit_drop_pct] || 0.05).to_s)

          if tracker.ready_to_trail?(pnl, min_profit) && tracker.trailing_stop_triggered?(pnl, drop_pct)
            execute_exit(position, tracker)
          end
        end
      end
    end

    def enforce_daily_circuit_breaker
      risk = risk_config
      limit_pct = BigDecimal((risk[:daily_loss_limit_pct] || 0).to_s)
      return if limit_pct <= 0

      begin
        funds = DhanHQ::Models::Funds.fetch
        pnl_today = if funds.respond_to?(:day_pnl)
                      BigDecimal(funds.day_pnl.to_s)
        elsif funds.is_a?(Hash)
                      BigDecimal((funds[:day_pnl] || 0).to_s)
        else
                      BigDecimal("0")
        end

        balance = if funds.respond_to?(:net_balance)
                    BigDecimal(funds.net_balance.to_s)
        elsif funds.respond_to?(:net_cash)
                    BigDecimal(funds.net_cash.to_s)
        elsif funds.is_a?(Hash)
                    BigDecimal((funds[:net_balance] || funds[:net_cash] || 0).to_s)
        else
                    BigDecimal("0")
        end

        return if balance <= 0

        loss_pct = (pnl_today / balance) * -1
        if pnl_today < 0 && loss_pct >= limit_pct
          Risk::CircuitBreaker.instance.trip!(reason: "daily loss limit reached: #{(loss_pct * 100).round(2)}%")
          Rails.logger.warn("Circuit breaker TRIPPED due to daily loss: #{pnl_today.to_s('F')} against balance #{balance.to_s('F')}")
        end
      rescue StandardError => e
        Rails.logger.warn("Daily circuit breaker check failed: #{e.class} - #{e.message}")
      end
    end

    def fetch_positions_indexed
      DhanHQ::Models::Position.active.each_with_object({}) do |position, map|
        security_id = position.respond_to?(:security_id) ? position.security_id : position[:security_id]
        map[security_id.to_s] = position if security_id
      end
    rescue StandardError => e
      Rails.logger.error("Failed to load active positions: #{e.class} - #{e.message}")
      {}
    end

    def current_ltp(tracker, position)
      segment = tracker.segment.presence
      segment ||= if position.respond_to?(:exchange_segment)
                    position.exchange_segment
      elsif position.is_a?(Hash)
                    position[:exchange_segment]
      end
      segment ||= tracker.instrument&.exchange_segment

      cached = Live::TickCache.ltp(segment, tracker.security_id)
      return BigDecimal(cached.to_s) if cached

      fetch_ltp(position, tracker)
    end

    def compute_pnl(tracker, position, ltp)
      quantity = tracker.quantity.to_i
      if quantity.zero? && position
        quantity = if position.respond_to?(:quantity)
                     position.quantity
        else
                     position[:quantity]
        end.to_i
      end
      return nil if quantity.zero?

      entry_price = tracker.entry_price || tracker.avg_price
      if entry_price.blank? && position
        entry_price = if position.respond_to?(:average_price)
                        position.average_price
        else
                        position[:average_price]
        end
      end
      return nil if entry_price.blank?

      (ltp - BigDecimal(entry_price.to_s)) * quantity
    rescue StandardError => e
      Rails.logger.error("Failed to compute PnL for tracker #{tracker.id}: #{e.class} - #{e.message}")
      nil
    end

    def compute_pnl_pct(tracker, ltp)
      entry_price = tracker.entry_price || tracker.avg_price
      return nil if entry_price.blank?

      (ltp - BigDecimal(entry_price.to_s)) / BigDecimal(entry_price.to_s)
    rescue StandardError
      nil
    end

    def fetch_ltp(position, tracker)
      segment =
        if position.respond_to?(:exchange_segment)
          position.exchange_segment
        elsif position.is_a?(Hash)
          position[:exchange_segment]
        end
      segment ||= tracker.instrument&.exchange_segment

      ltp = Live::TickCache.ltp(segment, tracker.security_id)
      return BigDecimal(ltp.to_s) if ltp

      nil
    end

    def should_lock_breakeven?(tracker, pnl_pct, threshold)
      return false if threshold.to_f <= 0
      return false if tracker.breakeven_locked?
      return false if pnl_pct.nil?

      pnl_pct >= BigDecimal(threshold.to_s)
    end

    def execute_exit(position, tracker)
      Rails.logger.info("Triggering trailing-stop exit for #{tracker.order_no} (PnL=#{tracker.last_pnl_rupees}).")
      exit_position(position, tracker)
      tracker.mark_exited!
    rescue StandardError => e
      Rails.logger.error("Failed to exit position #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def exit_position(position, tracker)
      if position.respond_to?(:exit!)
        position.exit!
      elsif position.respond_to?(:order_id)
        cancel_remote_order(position.order_id)
      else
        segment = tracker.segment.presence || tracker.instrument&.exchange_segment
        Orders::Placer.sell_market!(
          seg: segment,
          sid: tracker.security_id,
          qty: tracker.quantity.to_i,
          client_order_id: "AS-EXIT-#{tracker.order_no}-#{Time.current.to_i}"
        ) if segment.present?
      end
    end

    def risk_config
      AlgoConfig.fetch[:risk] || {}
    end

    def cancel_remote_order(order_id)
      order = DhanHQ::Models::Order.find(order_id)
      order.cancel
    rescue DhanHQ::Error => e
      Rails.logger.error("Failed to cancel order #{order_id}: #{e.message}")
      raise
    rescue StandardError => e
      Rails.logger.error("Unexpected error cancelling order #{order_id}: #{e.class} - #{e.message}")
      raise
    end
  end
end
