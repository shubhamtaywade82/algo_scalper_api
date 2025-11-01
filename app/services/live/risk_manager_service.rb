# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'
require 'ostruct'

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
        @thread.name = 'risk-manager-service'
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

    def evaluate_signal_risk(signal_data)
      confidence = signal_data[:confidence] || 0.0
      signal_data[:direction]
      entry_price = signal_data[:entry_price]
      stop_loss = signal_data[:stop_loss]
      signal_data[:take_profit]

      # Calculate risk level based on confidence and price levels
      risk_level = case confidence
                   when 0.8..1.0
                     :low
                   when 0.6...0.8
                     :medium
                   else
                     :high
                   end

      # Calculate maximum position size based on risk level
      max_position_size = case risk_level
                          when :low
                            100
                          when :medium
                            50
                          else
                            25
                          end

      # Use provided stop loss or calculate default
      recommended_stop_loss = stop_loss || (entry_price * 0.98) # 2% default stop loss

      {
        risk_level: risk_level,
        max_position_size: max_position_size,
        recommended_stop_loss: recommended_stop_loss
      }
    end

    private

    def monitor_loop
      while running?
        # Sync positions first to ensure we have all active positions tracked
        Live::PositionSyncService.instance.sync_positions!

        positions = fetch_positions_indexed
        enforce_hard_limits(positions)
        enforce_trailing_stops(positions)
        enforce_time_based_exit(positions)
        # Circuit breaker disabled - removed per requirement
        sleep LOOP_INTERVAL
      end
    rescue StandardError => e
      Rails.logger.error("RiskManagerService crashed: #{e.class} - #{e.message}")
      @running = false
    end

    def enforce_trailing_stops(positions = fetch_positions_indexed)
      risk = risk_config

      # Load all trackers with instruments in a single query with proper preloading
      trackers = PositionTracker.active.eager_load(:instrument).to_a

      trackers.each do |tracker|
        position = positions[tracker.security_id.to_s]
        ltp = current_ltp_with_freshness_check(tracker, position)
        next unless ltp

        pnl = compute_pnl(tracker, position, ltp)
        next unless pnl

        pnl_pct = compute_pnl_pct(tracker, ltp, position)

        # Store P&L in Redis for real-time tracking
        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)

        tracker.with_lock do
          tracker.update_pnl!(pnl, pnl_pct: pnl_pct)

          tracker.lock_breakeven! if should_lock_breakeven?(tracker, pnl_pct, risk[:breakeven_after_gain])

          min_profit = tracker.min_profit_lock(risk[:trail_step_pct] || 0)
          drop_pct = BigDecimal((risk[:exit_drop_pct] || 0.05).to_s)

          if tracker.ready_to_trail?(pnl, min_profit) && tracker.trailing_stop_triggered?(pnl, drop_pct)
            execute_exit(position, tracker, reason: "trailing stop (drop #{(drop_pct * 100).round(2)}%)")
          end
        end
      end
    end

    def enforce_hard_limits(positions = fetch_positions_indexed)
      risk = risk_config
      sl_pct = pct_value(risk[:sl_pct])
      tp_pct = pct_value(risk[:tp_pct])
      per_trade_pct = pct_value(risk[:per_trade_risk_pct])

      return if sl_pct <= 0 && tp_pct <= 0 && per_trade_pct <= 0

      # Load all trackers with instruments in a single query with proper preloading
      trackers = PositionTracker.active.eager_load(:instrument).to_a

      trackers.each do |tracker|
        position = positions[tracker.security_id.to_s]
        ltp = current_ltp(tracker, position)
        next unless ltp

        entry_price = tracker.entry_price || tracker.avg_price
        next if entry_price.blank?

        quantity = tracker.quantity.to_i
        if quantity.zero? && position
          quantity = if position.respond_to?(:quantity)
                       position.quantity
                     else
                       position[:quantity]
                     end.to_i
        end
        next if quantity <= 0

        entry = BigDecimal(entry_price.to_s)
        ltp_value = BigDecimal(ltp.to_s)
        reason = nil

        if sl_pct.positive?
          stop_price = entry * (BigDecimal(1) - sl_pct)
          reason = "hard stop-loss (#{(sl_pct * 100).round(2)}%)" if ltp_value <= stop_price
        end

        if reason.nil? && per_trade_pct.positive?
          invested = entry * quantity
          loss = [entry - ltp_value, BigDecimal(0)].max * quantity
          if invested.positive? && loss >= invested * per_trade_pct
            reason = "per-trade risk #{(per_trade_pct * 100).round(2)}%"
          end
        end

        if reason.nil? && tp_pct.positive?
          target_price = entry * (BigDecimal(1) + tp_pct)
          reason = "take-profit (#{(tp_pct * 100).round(2)}%)" if ltp_value >= target_price
        end

        next unless reason

        tracker.with_lock do
          next unless tracker.status == PositionTracker::STATUSES[:active]

          Rails.logger.info("Triggering exit for #{tracker.order_no} due to #{reason}.")
          execute_exit(position, tracker, reason: reason)
        end
      end
    end

    def enforce_time_based_exit(positions = fetch_positions_indexed)
      # Check if it's time for market close exit (3:20 PM)
      current_time = Time.current
      exit_time = Time.zone.parse('15:20') # 3:20 PM

      # Only enforce time-based exit during trading hours and after 3:20 PM
      return unless current_time >= exit_time

      # Check if we're still in trading hours (before 3:30 PM)
      market_close_time = Time.zone.parse('15:30') # 3:30 PM
      return if current_time >= market_close_time

      Rails.logger.info("[TimeExit] Enforcing time-based exit at #{current_time.strftime('%H:%M:%S')}")

      PositionTracker.active.includes(:instrument).find_each do |tracker|
        position = positions[tracker.security_id.to_s]

        tracker.with_lock do
          next unless tracker.status == PositionTracker::STATUSES[:active]

          Rails.logger.info("[TimeExit] Triggering time-based exit for #{tracker.order_no}")
          execute_exit(position, tracker, reason: 'time-based exit (3:20 PM)')
        end
      end
    rescue StandardError => e
      Rails.logger.error("Time-based exit enforcement failed: #{e.class} - #{e.message}")
    end

    # Circuit breaker disabled - removed per requirement
    # def enforce_daily_circuit_breaker
    #   # Method removed - circuit breaker functionality no longer needed
    # end

    def fetch_positions_indexed
      positions = DhanHQ::Models::Position.active.each_with_object({}) do |position, map|
        security_id = position.respond_to?(:security_id) ? position.security_id : position[:security_id]
        map[security_id.to_s] = position if security_id
      end
      Live::FeedHealthService.instance.mark_success!(:positions)
      positions
    rescue StandardError => e
      Rails.logger.error("Failed to load active positions: #{e.class} - #{e.message}")
      Live::FeedHealthService.instance.mark_failure!(:positions, error: e)
      {}
    end

    def current_ltp(tracker, position)
      # For options, fetch LTP directly from DhanHQ API to get correct option premium
      if position.respond_to?(:exchange_segment) && position.exchange_segment == 'NSE_FNO'
        begin
          response = DhanHQ::Models::MarketFeed.ltp({ 'NSE_FNO' => [tracker.security_id.to_i] })
          if response['status'] == 'success'
            option_data = response.dig('data', 'NSE_FNO', tracker.security_id)
            if option_data && option_data['last_price']
              ltp = BigDecimal(option_data['last_price'].to_s)
              Rails.logger.info("Fetched option LTP for #{tracker.security_id}: #{ltp}")

              # Store in Redis for future use
              Live::RedisPnlCache.instance.store_tick(
                segment: 'NSE_FNO',
                security_id: tracker.security_id,
                ltp: ltp,
                timestamp: Time.current
              )
              return ltp
            end
          end
        rescue StandardError => e
          Rails.logger.error("Failed to fetch option LTP for #{tracker.security_id}: #{e.message}")

          # For rate limiting errors, try to get from Redis cache first
          if e.message.include?('429')
            Rails.logger.warn("Rate limited - trying Redis cache for #{tracker.security_id}")
            cached = Live::TickCache.ltp('NSE_FNO', tracker.security_id)
            if cached
              ltp = BigDecimal(cached.to_s)
              Rails.logger.info("Using cached option LTP for #{tracker.security_id}: #{ltp}")

              # Store in Redis for future use
              Live::RedisPnlCache.instance.store_tick(
                segment: 'NSE_FNO',
                security_id: tracker.security_id,
                ltp: ltp,
                timestamp: Time.current
              )
              return ltp
            end
          end
        end
      end

      # Fallback to original method for non-options
      if tracker.instrument
        ltp = tracker.instrument.latest_ltp
        return ltp if ltp
      end

      # Fallback to manual fetching
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

    def current_ltp_with_freshness_check(tracker, position, max_age_seconds: 5)
      # Get segment and security_id for Redis key
      segment = position.respond_to?(:exchange_segment) ? position.exchange_segment : tracker.segment
      security_id = tracker.security_id

      # Check if tick is fresh in Redis cache
      if Live::RedisPnlCache.instance.is_tick_fresh?(segment: segment, security_id: security_id,
                                                     max_age_seconds: max_age_seconds)
        tick_data = Live::RedisPnlCache.instance.fetch_tick(segment: segment, security_id: security_id)
        return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)
      end

      # Fallback to current LTP method
      ltp = current_ltp(tracker, position)

      # If we got fresh LTP, store it in Redis
      if ltp && segment && security_id
        Live::RedisPnlCache.instance.store_tick(
          segment: segment,
          security_id: security_id,
          ltp: ltp,
          timestamp: Time.current
        )
      end

      ltp
    end

    def update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      # Ensure all values are present before storing
      return unless pnl && pnl_pct && ltp

      Live::RedisPnlCache.instance.store_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pnl_pct,
        ltp: ltp,
        timestamp: Time.current
      )
    rescue StandardError => e
      Rails.logger.error("Failed to update PnL in Redis for tracker #{tracker.id}: #{e.message}")
    end

    def compute_pnl(tracker, position, ltp)
      # For options, use the actual position quantity and cost price from DhanHQ
      if position.respond_to?(:net_qty) && position.respond_to?(:cost_price)
        quantity = position.net_qty.to_i
        cost_price = position.cost_price.to_f

        return nil if quantity.zero? || cost_price.zero?

        # Correct PnL calculation for options: (Current LTP - Cost Price) × Position Quantity
        pnl = (ltp - BigDecimal(cost_price.to_s)) * quantity

        Rails.logger.debug { "Option PnL calculation: (#{ltp} - #{cost_price}) × #{quantity} = #{pnl}" }
        return pnl
      end

      # Fallback to original calculation for non-option positions
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

    def compute_pnl_pct(tracker, ltp, position = nil)
      # For options, use cost price from DhanHQ position
      if position.respond_to?(:cost_price)
        cost_price = position.cost_price.to_f
        return nil if cost_price.zero?

        (ltp - BigDecimal(cost_price.to_s)) / BigDecimal(cost_price.to_s)
      else
        # Fallback to original calculation
        entry_price = tracker.entry_price || tracker.avg_price
        return nil if entry_price.blank?

        (ltp - BigDecimal(entry_price.to_s)) / BigDecimal(entry_price.to_s)
      end
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

    def execute_exit(position, tracker, reason: 'manual')
      pnl_display = tracker.last_pnl_rupees ? tracker.last_pnl_rupees.to_s : 'N/A'
      Rails.logger.info("Triggering exit for #{tracker.order_no} (reason: #{reason}, PnL=#{pnl_display}).")
      store_exit_reason(tracker, reason)

      # Attempt to exit position and check if successful
      exit_successful = exit_position(position, tracker)

      if exit_successful
        # Clear Redis cache for this tracker
        Live::RedisPnlCache.instance.clear_tracker(tracker.id)

        # Mark as exited only if order was placed successfully
        tracker.mark_exited!
        Rails.logger.info("Successfully exited position #{tracker.order_no}")
      else
        Rails.logger.error("Failed to place exit order for #{tracker.order_no} - position remains active")
        # Don't mark as exited if order placement failed
      end
    rescue StandardError => e
      Rails.logger.error("Failed to exit position #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def exit_position(position, tracker)
      if position.respond_to?(:exit!)
        position.exit!
        true
      elsif position.respond_to?(:order_id)
        cancel_remote_order(position.order_id)
        true
      else
        segment = tracker.segment.presence || tracker.instrument&.exchange_segment
        if segment.present?
          order = Orders.config.flat_position(
            segment: segment,
            security_id: tracker.security_id
          )
          order.present?
        else
          Rails.logger.error("Cannot exit position #{tracker.order_no}: no segment available")
          false
        end
      end
    rescue StandardError => e
      Rails.logger.error("Error in exit_position for #{tracker.order_no}: #{e.class} - #{e.message}")
      false
    end

    def store_exit_reason(tracker, reason)
      metadata = tracker.meta.is_a?(Hash) ? tracker.meta : {}
      tracker.update!(meta: metadata.merge('exit_reason' => reason, 'exit_triggered_at' => Time.current))
    rescue StandardError => e
      Rails.logger.warn("Failed to persist exit reason for #{tracker.order_no}: #{e.class} - #{e.message}")
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

    def pct_value(value)
      BigDecimal(value.to_s)
    rescue StandardError
      BigDecimal(0)
    end
  end
end
