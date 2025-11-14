# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'
require 'ostruct'

module Live
  class RiskManagerService
    # include Singleton

    LOOP_INTERVAL = 5
    API_CALL_STAGGER_SECONDS = 1.0 # Stagger API calls to avoid rate limits

    def initialize
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @watchdog_thread = Thread.new do
        loop do
          unless @thread&.alive?
            Rails.logger.warn("[RiskManagerService] Watchdog detected dead thread — restarting...")
            start
          end
          sleep 10
        end
      end
    end

    def start
      return if @running
      @running = true

      @thread = Thread.new do
        loop do
          break unless @running

          begin
            monitor_loop
          rescue => e
            Rails.logger.error("[RiskManager] #{e.class} - #{e.message}")
          end

          sleep LOOP_INTERVAL
        end
      end
    end

    def stop
      @running = false
      @thread&.kill
      @thread = nil
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

    def monitor_loop
      logger = Rails.logger
      last_paper_pnl_update = Time.current

      while running?
        # Sync positions first to ensure we have all active positions tracked
        # Live::PositionSyncService.instance.sync_positions!

        positions = fetch_positions_indexed
        enforce_hard_limits(positions)
        enforce_trailing_stops(positions)
        enforce_time_based_exit(positions)

        # Update PnL for all active paper positions every 1 minute
        # This ensures paper_trading_stats shows current unrealized PnL
        # Also ensures all active positions (paper and live) have their PnL in Redis
        if Time.current - last_paper_pnl_update >= 1.minute
          update_paper_positions_pnl
          # Also ensure all active positions have their PnL in Redis
          ensure_all_positions_in_redis
          last_paper_pnl_update = Time.current
        end

        # Circuit breaker disabled - removed per requirement
        sleep LOOP_INTERVAL
      end
    rescue StandardError => e
      message = "RiskManagerService crashed: #{e.class} - #{e.message}"
      logger.error(message)
      global_logger = Rails.logger
      global_logger.error(message) unless global_logger.equal?(logger)
      @running = false
    end

    def sleep(seconds)
      Kernel.sleep(seconds)
    end

    # def enforce_trailing_stops(positions = fetch_positions_indexed)
    #   risk = risk_config

    #   # Load all trackers - can't eagerly load polymorphic :watchable, so load instrument separately
    #   trackers = PositionTracker.active.includes(:instrument).to_a

    #   trackers.each_with_index do |tracker, index|
    #     # Stagger API calls to avoid rate limits
    #     sleep API_CALL_STAGGER_SECONDS if index.positive?

    #     position = positions[tracker.security_id.to_s]
    #     tracker.hydrate_pnl_from_cache!

    #     ltp = current_ltp_with_freshness_check(tracker, position)
    #     next unless ltp

    #     pnl = compute_pnl(tracker, position, ltp)
    #     pnl_pct = compute_pnl_pct(tracker, ltp, position) if pnl

    #     # Update PnL in Redis for all positions (not just those with valid PnL)
    #     # This ensures all active positions have their PnL cached in Redis
    #     next unless pnl && ltp

    #     tracker.with_lock do
    #       next unless tracker.status == PositionTracker::STATUSES[:active]

    #       tracker.cache_live_pnl(pnl, pnl_pct: pnl_pct)
    #       update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)

    #       tracker.lock_breakeven! if should_lock_breakeven?(tracker, pnl_pct, risk[:breakeven_after_gain])

    #       min_profit = tracker.min_profit_lock(risk[:trail_step_pct] || 0)
    #       drop_pct = BigDecimal((risk[:exit_drop_pct] || 0.05).to_s)

    #       if tracker.ready_to_trail?(pnl, min_profit) && tracker.trailing_stop_triggered?(pnl, drop_pct)
    #         # Check minimum profit requirement before allowing trailing stop exit
    #         min_profit_rupees = BigDecimal((risk[:min_profit_rupees] || 0).to_s)
    #         if min_profit_rupees.positive? && pnl < min_profit_rupees
    #           Rails.logger.debug { "[RiskManager] Trailing stop triggered for #{tracker.order_no}, but PnL (₹#{pnl.round(2)}) < minimum profit (₹#{min_profit_rupees}) - holding position" }
    #           next # Skip exit, wait for minimum profit
    #         end
    #         execute_exit(position, tracker, reason: "trailing stop (drop #{(drop_pct * 100).round(2)}%)")
    #       end
    #     end
    #   end
    # end

    def enforce_trailing_stops(exit_engine:)
      risk = risk_config
      drop_threshold = risk[:exit_drop_pct].to_f

      PositionTracker.active.find_each do |tracker|
        snap = pnl_snapshot(tracker)
        next unless snap

        pnl = snap[:pnl]
        hwm = snap[:hwm_pnl]
        next if hwm.nil? || hwm.zero?

        drop_pct = (hwm - pnl) / hwm

        if drop_pct >= drop_threshold
          exit_engine.execute_exit(tracker, "TRAILING STOP drop=#{drop_pct.round(3)}")
          next
        end
      end
    end


    def enforce_hard_limits(exit_engine:)
      risk = risk_config
      sl_pct = risk[:sl_pct].to_f
      tp_pct = risk[:tp_pct].to_f

      PositionTracker.active.find_each do |tracker|
        snapshot = pnl_snapshot(tracker)
        next unless snapshot

        pnl     = snapshot[:pnl]
        pnl_pct = snapshot[:pnl_pct]

        # STOP LOSS
        if pnl_pct <= -sl_pct
          exit_engine.execute_exit(tracker, "SL HIT #{(pnl_pct*100).round(2)}%")
          next
        end

        # TAKE PROFIT
        if pnl_pct >= tp_pct
          exit_engine.execute_exit(tracker, "TP HIT #{(pnl_pct*100).round(2)}%")
          next
        end
      end
    end


    # # Replace the existing enforce_hard_limits method with this one
    # def enforce_hard_limits(positions = fetch_positions_indexed)
    #   risk = risk_config
    #   sl_pct = pct_value(risk[:sl_pct])
    #   tp_pct = pct_value(risk[:tp_pct])
    #   per_trade_pct = pct_value(risk[:per_trade_risk_pct])

    #   return if sl_pct <= 0 && tp_pct <= 0 && per_trade_pct <= 0

    #   trackers = PositionTracker.active.includes(:instrument).to_a

    #   trackers.each_with_index do |tracker, index|
    #     # Stagger calls to be polite with rate limits
    #     sleep API_CALL_STAGGER_SECONDS if index.positive?

    #     position = positions[tracker.security_id.to_s]
    #     tracker.hydrate_pnl_from_cache!

    #     # Try to resolve an actionable LTP (with freshness fallback inside)
    #     ltp = current_ltp(tracker, position)
    #     # Also try a freshness-checked LTP (used for strict comparisons)
    #     fresh_ltp = current_ltp_with_freshness_check(tracker, position, max_age_seconds: 5) rescue ltp

    #     # Prefer fresh if available
    #     usable_ltp = fresh_ltp || ltp

    #     # Attempt best-effort pnl% if we don't have LTP
    #     pnl_value = (usable_ltp ? compute_pnl(tracker, position, usable_ltp) : nil)
    #     pnl_pct_value = (usable_ltp ? compute_pnl_pct(tracker, usable_ltp, position) : nil)

    #     # Fallback for paper: use last persisted pnl_pct
    #     if usable_ltp.nil? && pnl_pct_value.nil? && tracker.paper? && tracker.last_pnl_pct
    #       pnl_pct_value = BigDecimal(tracker.last_pnl_pct.to_s) / 100
    #     end

    #     Rails.logger.debug do
    #       "[RiskManager][Check] tracker=#{tracker.id} seg=#{tracker.segment} sid=#{tracker.security_id} " \
    #       "entry=#{tracker.entry_price.inspect} qty=#{tracker.quantity.to_i} ltp=#{usable_ltp.inspect} pnl=#{pnl_value.inspect} pnl_pct=#{pnl_pct_value.inspect}"
    #     end

    #     # Update redis pnl cache for monitor visibility even if we don't exit
    #     tracker.with_lock do
    #       next unless tracker.status == PositionTracker::STATUSES[:active]

    #       tracker.cache_live_pnl(pnl_value, pnl_pct: pnl_pct_value)
    #       update_pnl_in_redis(tracker, pnl_value, pnl_pct_value, usable_ltp)
    #     end

    #     # If we still have nothing usable, skip and log reason
    #     if usable_ltp.nil? && pnl_pct_value.nil?
    #       Rails.logger.debug("[RiskManager] Skipping #{tracker.order_no} (#{tracker.id}) - no LTP and no fallback PnL%")
    #       next
    #     end

    #     reason = nil

    #     entry_price = tracker.entry_price || tracker.avg_price
    #     if entry_price.blank? && position
    #       entry_price = position.respond_to?(:cost_price) ? position.cost_price : (position[:average_price] || position[:cost_price])
    #     end
    #     next if entry_price.blank?

    #     quantity = tracker.quantity.to_i
    #     if quantity.zero? && position
    #       quantity = if position.respond_to?(:net_qty) then position.net_qty.to_i
    #                 elsif position.respond_to?(:quantity) then position.quantity.to_i
    #                 else (position[:quantity] || position[:net_qty] || 0).to_i
    #                 end
    #     end
    #     next if quantity <= 0

    #     entry = BigDecimal(entry_price.to_s)
    #     ltp_value = usable_ltp ? BigDecimal(usable_ltp.to_s) : nil

    #     # STOP LOSS: prefer live LTP comparison, fallback to PnL%
    #     if sl_pct.positive?
    #       if ltp_value
    #         stop_price = entry * (BigDecimal(1) - sl_pct)
    #         if ltp_value <= stop_price
    #           reason = "hard stop-loss (#{(sl_pct * 100).round(2)}%) - ltp #{ltp_value} <= stop_price #{stop_price}"
    #         end
    #       elsif pnl_pct_value && pnl_pct_value <= -sl_pct
    #         reason = "hard stop-loss (#{(sl_pct * 100).round(2)}%) - pnl_pct #{(pnl_pct_value * 100).round(2)}%"
    #       end
    #     end

    #     # PER-TRADE RISK (absolute rupee loss cap)
    #     if reason.nil? && per_trade_pct.positive? && ltp_value
    #       invested = entry * quantity
    #       loss_per_unit = [entry - ltp_value, BigDecimal(0)].max
    #       loss = loss_per_unit * quantity
    #       if invested.positive? && loss >= invested * per_trade_pct
    #         reason = "per-trade risk #{(per_trade_pct * 100).round(2)}% - potential loss #{loss.to_f.round(2)} >= allowed #{(invested * per_trade_pct).to_f.round(2)}"
    #       end
    #     end

    #     # TAKE PROFIT
    #     if reason.nil? && tp_pct.positive? && ltp_value
    #       target_price = entry * (BigDecimal(1) + tp_pct)
    #       if ltp_value >= target_price
    #         min_profit = BigDecimal((risk[:min_profit_rupees] || 0).to_s)
    #         if min_profit.positive? && pnl_value && pnl_value < min_profit
    #           Rails.logger.debug { "[RiskManager] TP reached for #{tracker.order_no}, but pnl ₹#{pnl_value.round(2)} < min_profit ₹#{min_profit}" }
    #         else
    #           reason = "take-profit (#{(tp_pct * 100).round(2)}%) - ltp #{ltp_value} >= target #{target_price}"
    #         end
    #       end
    #     end

    #     # If reason found -> execute exit (inside lock)
    #     if reason
    #       Rails.logger.info("[RiskManager] Exit condition triggered for #{tracker.order_no} (#{tracker.id}): #{reason}")
    #       tracker.with_lock do
    #         next unless tracker.status == PositionTracker::STATUSES[:active]
    #         begin
    #           execute_exit(position, tracker, reason: reason)
    #         rescue => e
    #           Rails.logger.error("[RiskManager] Failed to execute exit for #{tracker.order_no}: #{e.class} - #{e.message}")
    #         end
    #       end
    #     end
    #   end
    # end


    def enforce_time_based_exit(positions = nil, exit_engine: nil)
      # allow caller to pass positions or let this method fetch them
      positions ||= fetch_positions_indexed

      risk = risk_config
      exit_time = parse_time_hhmm(risk[:time_exit_hhmm] || '15:20')
      return unless exit_time

      current_time = Time.current
      return unless current_time >= exit_time

      market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
      return if market_close_time && current_time >= market_close_time

      PositionTracker.active.includes(:instrument).find_each do |tracker|
        position = positions[tracker.security_id.to_s]

        tracker.with_lock do
          next unless tracker.status == PositionTracker::STATUSES[:active]

          tracker.hydrate_pnl_from_cache!

          # For time-based exits, check minimum profit if position is in profit
          if tracker.last_pnl_rupees.present? && tracker.last_pnl_rupees.positive?
            min_profit_rupees = BigDecimal((risk[:min_profit_rupees] || 0).to_s)
            if min_profit_rupees.positive? && tracker.last_pnl_rupees < min_profit_rupees
              Rails.logger.info("[RiskManager] Time-based exit skipped for #{tracker.order_no} - PnL (₹#{tracker.last_pnl_rupees.round(2)}) < minimum profit (₹#{min_profit_rupees})")
              next
            end
          end

          reason = "time-based exit (#{exit_time.strftime('%H:%M')})"
          Rails.logger.info("[RiskManager] Time-based exit for #{tracker.order_no} (#{tracker.symbol})")

          if exit_engine
            exit_engine.execute_exit(tracker, reason)
          else
            # backward compatible: use internal executor
            execute_exit(position, tracker, reason: reason)
          end
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
      # In paper trading mode, return empty hash - paper positions don't exist in DhanHQ
      return {} if paper_trading_enabled?

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

    def paper_trading_enabled?
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
    end

    def current_ltp(tracker, position)
      # For paper positions, use paper LTP method
      return get_paper_ltp(tracker) if tracker.paper?

      # For options, fetch LTP directly from DhanHQ API to get correct option premium
      if position.respond_to?(:exchange_segment) && position.exchange_segment == 'NSE_FNO'
        begin
          response = DhanHQ::Models::MarketFeed.ltp({ 'NSE_FNO' => [tracker.security_id.to_i] })
          if response['status'] == 'success'
            option_data = response.dig('data', 'NSE_FNO', tracker.security_id)
            if option_data && option_data['last_price']
              ltp = BigDecimal(option_data['last_price'].to_s)
              # Rails.logger.info("Fetched option LTP for #{tracker.security_id}: #{ltp}")

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
              # Rails.logger.info("Using cached option LTP for #{tracker.security_id}: #{ltp}")

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
      tradable = tracker.tradable
      if tradable
        ltp = tradable.ltp
        return ltp if ltp
      end

      # Fallback to manual fetching
      segment = tracker.segment.presence
      segment ||= if position.respond_to?(:exchange_segment)
                    position.exchange_segment
                  elsif position.is_a?(Hash)
                    position[:exchange_segment]
                  end
      segment ||= tradable&.exchange_segment || tracker.instrument&.exchange_segment

      cached = Live::TickCache.ltp(segment, tracker.security_id)
      return BigDecimal(cached.to_s) if cached

      fetch_ltp(position, tracker)
    end

    def current_ltp_with_freshness_check(tracker, position, max_age_seconds: 5)
      # For paper positions, use paper LTP method
      return get_paper_ltp(tracker) if tracker.paper?

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

    # def update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
    #   # Ensure all values are present before storing
    #   return unless pnl && ltp && ltp.to_f.positive?

    #   Live::RedisPnlCache.instance.store_pnl(
    #     tracker_id: tracker.id,
    #     pnl: pnl,
    #     pnl_pct: pnl_pct,
    #     ltp: ltp,
    #     hwm: tracker.high_water_mark_pnl,
    #     timestamp: Time.current
    #   )
    # rescue StandardError => e
    #   Rails.logger.error("Failed to update PnL in Redis for tracker #{tracker.id}: #{e.message}")
    # end

    def update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      # Defer to new updater; keep compatibility for now
      return unless pnl && ltp && ltp.to_f.positive?

      Live::PnlUpdaterService.instance.cache_intermediate_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pnl_pct,
        ltp: ltp,
        hwm: tracker.high_water_mark_pnl
      )
    end


    def compute_pnl(tracker, position, ltp)
      # For options, use the actual position quantity and cost price from DhanHQ
      if position.respond_to?(:net_qty) && position.respond_to?(:cost_price)
        quantity = position.net_qty.to_i
        cost_price = position.cost_price.to_f

        return nil if quantity.zero? || cost_price.zero?

        # Correct PnL calculation for options: (Current LTP - Cost Price) × Position Quantity
        pnl = (ltp - BigDecimal(cost_price.to_s)) * quantity

        # Rails.logger.debug { "Option PnL calculation: (#{ltp} - #{cost_price}) × #{quantity} = #{pnl}" }
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
      Rails.logger.info("[RiskManager] Exiting #{tracker.order_no} (#{tracker.symbol}): #{reason}, PnL=#{pnl_display}")
      store_exit_reason(tracker, reason)

      # Attempt to exit position and get exit price if available
      exit_result = exit_position(position, tracker)
      exit_successful = exit_result.is_a?(Hash) ? exit_result[:success] : exit_result
      exit_price = exit_result.is_a?(Hash) ? exit_result[:exit_price] : nil

      if exit_successful
        # Mark as exited only if order was placed successfully
        # Redis cache will be cleared in mark_exited! AFTER PnL is persisted
        tracker.mark_exited!(exit_price: exit_price)
        # Rails.logger.info("Successfully exited position #{tracker.order_no}")
      else
        Rails.logger.error("Failed to place exit order for #{tracker.order_no} - position remains active")
        # Don't mark as exited if order placement failed
      end
    rescue StandardError => e
      Rails.logger.error("Failed to exit position #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def pnl_snapshot(tracker)
      Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
    end


    def exit_position(position, tracker)
      # Paper trading: Just update the position with exit price, no real order
      if tracker.paper?
        current_ltp_value = get_paper_ltp(tracker)
        if current_ltp_value
          exit_price = BigDecimal(current_ltp_value.to_s)
          entry = BigDecimal(tracker.entry_price.to_s)
          qty = tracker.quantity.to_i
          pnl = (exit_price - entry) * qty
          pnl_pct = ((exit_price - entry) / entry * 100).round(2)

          # Calculate high water mark
          hwm = tracker.high_water_mark_pnl || BigDecimal(0)
          hwm = [hwm, pnl].max

          tracker.update!(
            last_pnl_rupees: pnl,
            last_pnl_pct: pnl_pct,
            high_water_mark_pnl: hwm,
            avg_price: exit_price
          )

          Rails.logger.info("[RiskManager] Paper exit for #{tracker.order_no}: exit_price=₹#{exit_price}, pnl=₹#{pnl}, pnl_pct=#{pnl_pct}%")
          return { success: true, exit_price: exit_price }
        else
          Rails.logger.warn("[RiskManager] Cannot get LTP for paper exit of #{tracker.order_no}")
          return { success: false, exit_price: nil }
        end
      end

      # Live trading: Place real exit order and get LTP as fallback for exit price
      exit_price = nil
      exit_successful = false

      if position.respond_to?(:exit!)
        exit_successful = position.exit!
      elsif position.respond_to?(:order_id)
        exit_successful = cancel_remote_order(position.order_id)
      else
        segment = tracker.segment.presence || tracker.tradable&.exchange_segment || tracker.instrument&.exchange_segment
        if segment.present?
          order = Orders.config.flat_position(
            segment: segment,
            security_id: tracker.security_id
          )
          exit_successful = order.present?
        else
          Rails.logger.error("Cannot exit position #{tracker.order_no}: no segment available")
        end
      end

      # For live positions, try to get current LTP as exit price fallback
      if exit_successful && exit_price.nil?
        ltp_value = current_ltp(tracker)
        exit_price = BigDecimal(ltp_value.to_s) if ltp_value.present? && ltp_value.to_f.positive?
      end

      { success: exit_successful, exit_price: exit_price }
    rescue StandardError => e
      Rails.logger.error("Error in exit_position for #{tracker.order_no}: #{e.class} - #{e.message}")
      { success: false, exit_price: nil }
    end

    def update_paper_positions_pnl
      # Update PnL for all active paper positions and persist to database
      # This ensures paper_trading_stats shows current unrealized PnL
      # Also ensures all paper positions have their PnL in Redis
      paper_trackers = PositionTracker.paper.active.includes(:instrument).to_a
      return if paper_trackers.empty?

      updated_count = 0
      failed_count = 0
      paper_trackers.each do |tracker|
        next unless tracker.entry_price.present? && tracker.quantity.present?

        ltp = get_paper_ltp(tracker)
        unless ltp
          Rails.logger.debug { "[RiskManager] No LTP available for paper position #{tracker.order_no} (#{tracker.symbol})" }
          failed_count += 1
          next
        end

        entry = BigDecimal(tracker.entry_price.to_s)
        exit_price = BigDecimal(ltp.to_s)
        qty = tracker.quantity.to_i
        pnl = (exit_price - entry) * qty
        pnl_pct = entry.positive? ? ((exit_price - entry) / entry * 100).round(2) : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct,
          high_water_mark_pnl: hwm
        )

        # Also update in Redis for consistency
        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
        updated_count += 1
      rescue StandardError => e
        Rails.logger.error("[RiskManager] Failed to update PnL for paper position #{tracker.order_no}: #{e.message}")
        failed_count += 1
      end

      return unless updated_count.positive? || failed_count.positive?

      Rails.logger.info("[RiskManager] Paper PnL update: #{updated_count}/#{paper_trackers.count} updated#{", #{failed_count} failed" if failed_count.positive?}")
    end

    def ensure_all_positions_in_redis
      # Ensure all active positions (both paper and live) have their PnL in Redis
      # This is a safety net to catch any positions that might have been missed
      all_trackers = PositionTracker.active.includes(:instrument).to_a
      return if all_trackers.empty?

      positions = fetch_positions_indexed
      missing_in_redis = []

      all_trackers.each do |tracker|
        # Check if this tracker has PnL in Redis (check if key exists, not if pnl is truthy)
        redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
        # If Redis has data (even if pnl is 0), skip - it means it was already processed
        if redis_pnl && (Time.current.to_i - (redis_pnl[:timestamp] || 0)) < 10
          next
        end

        # Try to update it
        position = positions[tracker.security_id.to_s]
        tracker.hydrate_pnl_from_cache!

        ltp = if tracker.paper?
                get_paper_ltp(tracker)
              else
                current_ltp(tracker, position)
              end

        unless ltp
          Rails.logger.debug { "[RiskManager] No LTP available for tracker #{tracker.id} (#{tracker.order_no}) - cannot update Redis PnL" }
          next
        end

        pnl = compute_pnl(tracker, position, ltp)
        unless pnl
          Rails.logger.debug { "[RiskManager] Cannot compute PnL for tracker #{tracker.id} (#{tracker.order_no}) - entry_price or quantity missing" }
          next
        end

        pnl_pct = compute_pnl_pct(tracker, ltp, position)

        # Update in Redis
        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
        missing_in_redis << tracker.id
      rescue StandardError => e
        Rails.logger.error("[RiskManager] Failed to ensure Redis PnL for tracker #{tracker.id}: #{e.message}")
      end

      return unless missing_in_redis.any?

      Rails.logger.info("[RiskManager] Ensured Redis PnL for #{missing_in_redis.count} positions that were missing: #{missing_in_redis.join(', ')}")
    end

    def get_paper_ltp(tracker)
      segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
      security_id = tracker.security_id

      return nil unless segment.present? && security_id.present?

      # Try WebSocket cache first (fastest)
      cached = Live::TickCache.ltp(segment, security_id)
      if cached
        Rails.logger.debug { "[RiskManager] Paper LTP from cache for #{tracker.order_no}: ₹#{cached}" }
        return BigDecimal(cached.to_s)
      end

      # Try Redis PnL cache
      tick_data = Live::RedisPnlCache.instance.fetch_tick(segment: segment, security_id: security_id)
      if tick_data&.dig(:ltp)
        Rails.logger.debug { "[RiskManager] Paper LTP from Redis for #{tracker.order_no}: ₹#{tick_data[:ltp]}" }
        return BigDecimal(tick_data[:ltp].to_s)
      end

      # Try tradable's fetch method (derivative or instrument)
      tradable = tracker.tradable
      if tradable
        ltp = tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        if ltp
          Rails.logger.debug { "[RiskManager] Paper LTP from API for #{tracker.order_no}: ₹#{ltp}" }
          return BigDecimal(ltp.to_s)
        end
      end

      # Fallback: Direct API call
      begin
        response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
        if response['status'] == 'success'
          option_data = response.dig('data', segment, security_id.to_s)
          if option_data && option_data['last_price']
            ltp = BigDecimal(option_data['last_price'].to_s)
            Rails.logger.debug { "[RiskManager] Paper LTP from direct API for #{tracker.order_no}: ₹#{ltp}" }
            return ltp
          end
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] Failed to fetch paper LTP for #{tracker.order_no}: #{e.message}")
      end

      nil
    end

    def store_exit_reason(tracker, reason)
      metadata = tracker.meta.is_a?(Hash) ? tracker.meta : {}
      tracker.update!(meta: metadata.merge('exit_reason' => reason, 'exit_triggered_at' => Time.current))
    rescue StandardError => e
      Rails.logger.warn("Failed to persist exit reason for #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def parse_time_hhmm(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError
      Rails.logger.warn("[RiskManager] Invalid time format provided: #{value}")
      nil
    end

    def risk_config
      raw = AlgoConfig.fetch[:risk]
      return {} if raw.blank?

      config = raw.dup
      config[:stop_loss_pct] = raw[:stop_loss_pct] || raw[:sl_pct]
      config[:take_profit_pct] = raw[:take_profit_pct] || raw[:tp_pct]
      config[:sl_pct] = config[:stop_loss_pct]
      config[:tp_pct] = config[:take_profit_pct]
      config[:breakeven_after_gain] = raw.key?(:breakeven_after_gain) ? raw[:breakeven_after_gain] : 0
      config[:trail_step_pct] = raw[:trail_step_pct] if raw.key?(:trail_step_pct)
      config[:exit_drop_pct] = raw[:exit_drop_pct] if raw.key?(:exit_drop_pct)
      config[:time_exit_hhmm] = raw[:time_exit_hhmm] if raw.key?(:time_exit_hhmm)
      config[:market_close_hhmm] = raw[:market_close_hhmm] if raw.key?(:market_close_hhmm)
      config[:min_profit_rupees] = raw[:min_profit_rupees] if raw.key?(:min_profit_rupees)
      config
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
