# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'
require 'ostruct'

module Live
  # Responsible for monitoring active PositionTracker entries, keeping PnL up-to-date in Redis,
  # and enforcing exits according to configured risk rules.
  #
  # Behaviour:
  # - If an external ExitEngine is provided (recommended), RiskManagerService will NOT place exits itself.
  #   Instead ExitEngine calls the enforcement methods and RiskManagerService supplies helper functions.
  # - If no external ExitEngine is provided, RiskManagerService will execute exits itself (backwards compatibility).
  class RiskManagerService
    LOOP_INTERVAL = 5
    API_CALL_STAGGER_SECONDS = 1.0

    def initialize(exit_engine: nil)
      @exit_engine = exit_engine
      @mutex = Mutex.new
      @running = false
      @thread = nil

      # Watchdog ensures service thread is restarted if it dies (lightweight)
      @watchdog_thread = Thread.new do
        loop do
          unless @thread&.alive?
            Rails.logger.warn('[RiskManagerService] Watchdog detected dead thread — restarting...')
            start
          end
          sleep 10
        end
      end
    end

    # Start monitoring loop (non-blocking)
    def start
      return if @running

      @running = true

      @thread = Thread.new do
        Thread.current.name = 'risk-manager'
        last_paper_pnl_update = Time.current

        loop do
          break unless @running

          begin
            monitor_loop(last_paper_pnl_update)
            # update timestamp after paper update occurred inside monitor_loop
            last_paper_pnl_update = Time.current
          rescue StandardError => e
            Rails.logger.error("[RiskManagerService] monitor_loop crashed: #{e.class} - #{e.message}\n#{e.backtrace.first(8).join("\n")}")
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

    # Lightweight risk evaluation helper (unchanged semantics)
    def evaluate_signal_risk(signal_data)
      confidence = signal_data[:confidence] || 0.0
      entry_price = signal_data[:entry_price]
      stop_loss = signal_data[:stop_loss]

      risk_level =
        case confidence
        when 0.8..1.0 then :low
        when 0.6...0.8 then :medium
        else :high
        end

      max_position_size =
        case risk_level
        when :low then 100
        when :medium then 50
        else 25
        end

      recommended_stop_loss = stop_loss || (entry_price * 0.98)

      { risk_level: risk_level, max_position_size: max_position_size, recommended_stop_loss: recommended_stop_loss }
    end

    private

    # Central monitoring loop: keep PnL and caches fresh.
    # DO NOT perform exit dispatching here when an external ExitEngine exists — ExitEngine will call enforcement methods.
    def monitor_loop(last_paper_pnl_update)
      # Keep Redis/DB PnL fresh
      update_paper_positions_pnl_if_due(last_paper_pnl_update)
      ensure_all_positions_in_redis

      # Backwards-compatible enforcement: if there is no external ExitEngine, run enforcement here
      return unless @exit_engine.nil?

      enforce_hard_limits(exit_engine: self)
      enforce_trailing_stops(exit_engine: self)
      enforce_time_based_exit(exit_engine: self)
    end

    # Called by external ExitEngine or internally (when used standalone).
    # Exits triggered by enforcement logic call this method on the supplied exit_engine.
    # This method implements legacy behaviour for self-managed exits.
    def execute_exit(tracker, reason)
      # This method implements the fallback exit path when RiskManagerService is self-executing.
      # Prefer using external ExitEngine with Orders::OrderRouter for real deployments.
      Rails.logger.info("[RiskManager] execute_exit invoked for #{tracker.order_no} reason=#{reason}")

      begin
        store_exit_reason(tracker, reason)
        exit_result = exit_position(nil, tracker)
        exit_successful = exit_result.is_a?(Hash) ? exit_result[:success] : exit_result
        exit_price = exit_result.is_a?(Hash) ? exit_result[:exit_price] : nil

        if exit_successful
          tracker.mark_exited!(exit_price: exit_price, exit_reason: reason)
          Rails.logger.info("[RiskManager] Successfully exited #{tracker.order_no} (#{tracker.id}) via internal executor")
          true
        else
          Rails.logger.error("[RiskManager] Failed to exit #{tracker.order_no} via internal executor")
          false
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] execute_exit failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        false
      end
    end

    # Enforcement methods always accept an exit_engine keyword. They do not fetch positions from caller.
    # If exit_engine is provided, they will delegate the actual exit to it. Otherwise they call internal execute_exit.
    public

    def enforce_trailing_stops(exit_engine:)
      risk = risk_config
      drop_threshold = begin
        BigDecimal(risk[:exit_drop_pct].to_s)
      rescue StandardError
        BigDecimal(0)
      end

      PositionTracker.active.find_each do |tracker|
        snap = pnl_snapshot(tracker)
        next unless snap

        pnl = snap[:pnl]
        hwm = snap[:hwm_pnl]
        next if hwm.nil? || hwm.zero?

        drop_pct = (hwm - pnl) / hwm
        if drop_pct >= drop_threshold
          reason = "TRAILING STOP drop=#{drop_pct.round(3)}"
          dispatch_exit(exit_engine, tracker, reason)
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_trailing_stops error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end
    end

    def enforce_hard_limits(exit_engine:)
      risk = risk_config
      sl_pct = begin
        BigDecimal(risk[:sl_pct].to_s)
      rescue StandardError
        BigDecimal(0)
      end
      tp_pct = begin
        BigDecimal(risk[:tp_pct].to_s)
      rescue StandardError
        BigDecimal(0)
      end

      PositionTracker.active.find_each do |tracker|
        snapshot = pnl_snapshot(tracker)
        next unless snapshot

        pnl_pct = snapshot[:pnl_pct]
        next if pnl_pct.nil?

        if pnl_pct <= -sl_pct
          reason = "SL HIT #{(pnl_pct * 100).round(2)}%"
          dispatch_exit(exit_engine, tracker, reason)
          next
        end

        if pnl_pct >= tp_pct
          reason = "TP HIT #{(pnl_pct * 100).round(2)}%"
          dispatch_exit(exit_engine, tracker, reason)
          next
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_hard_limits error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end
    end

    def enforce_time_based_exit(exit_engine:)
      risk = risk_config
      exit_time = parse_time_hhmm(risk[:time_exit_hhmm] || '15:20')
      return unless exit_time

      now = Time.current
      return unless now >= exit_time

      market_close_time = parse_time_hhmm(risk[:market_close_hhmm] || '15:30')
      return if market_close_time && now >= market_close_time

      PositionTracker.active.find_each do |tracker|
        tracker.hydrate_pnl_from_cache!
        if tracker.last_pnl_rupees.present? && tracker.last_pnl_rupees.positive?
          min_profit = begin
            BigDecimal((risk[:min_profit_rupees] || 0).to_s)
          rescue StandardError
            BigDecimal(0)
          end
          if min_profit.positive? && tracker.last_pnl_rupees < min_profit
            Rails.logger.info("[RiskManager] Time-based exit skipped for #{tracker.order_no} - PnL < min_profit")
            next
          end
        end

        reason = "time-based exit (#{exit_time.strftime('%H:%M')})"
        dispatch_exit(exit_engine, tracker, reason)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] enforce_time_based_exit error for tracker=#{tracker.id}: #{e.class} - #{e.message}")
      end
    end

    private

    # Helper that centralizes exit dispatching logic.
    # If exit_engine is an object responding to execute_exit, delegate to it.
    # If exit_engine == self (or nil) we fallback to internal execute_exit implementation.
    def dispatch_exit(exit_engine, tracker, reason)
      if exit_engine && exit_engine.respond_to?(:execute_exit) && !exit_engine.equal?(self)
        begin
          exit_engine.execute_exit(tracker, reason)
        rescue StandardError => e
          Rails.logger.error("[RiskManager] external exit_engine failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        end
      else
        # self-managed execution (backwards compatibility)
        execute_exit(tracker, reason)
      end
    end

    # --- Position/market helpers ---

    # Fetch live broker positions keyed by security_id (string). Returns {} on paper mode or failure.
    def fetch_positions_indexed
      return {} if paper_trading_enabled?

      positions = DhanHQ::Models::Position.active.each_with_object({}) do |position, map|
        security_id = position.respond_to?(:security_id) ? position.security_id : position[:security_id]
        map[security_id.to_s] = position if security_id
      end
      begin
        Live::FeedHealthService.instance.mark_success!(:positions)
      rescue StandardError
        nil
      end
      positions
    rescue StandardError => e
      Rails.logger.error("[RiskManager] fetch_positions_indexed failed: #{e.class} - #{e.message}")
      begin
        Live::FeedHealthService.instance.mark_failure!(:positions, error: e)
      rescue StandardError
        nil
      end
      {}
    end

    def paper_trading_enabled?
      AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
    rescue StandardError
      false
    end

    # Returns a cached pnl snapshot for tracker (expects Redis cache to be maintained elsewhere)
    def pnl_snapshot(tracker)
      Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
    rescue StandardError => e
      Rails.logger.error("[RiskManager] pnl_snapshot error for #{tracker.id}: #{e.class} - #{e.message}")
      nil
    end

    def update_paper_positions_pnl_if_due(last_update_time)
      # if last_update_time is nil or stale, update now
      return unless Time.current - (last_update_time || Time.zone.at(0)) >= 1.minute

      update_paper_positions_pnl
    rescue StandardError => e
      Rails.logger.error("[RiskManager] update_paper_positions_pnl_if_due failed: #{e.class} - #{e.message}")
    end

    # Update PnL for all paper trackers and cache in Redis (same semantics as before)
    def update_paper_positions_pnl
      paper_trackers = PositionTracker.paper.active.includes(:instrument).to_a
      return if paper_trackers.empty?

      paper_trackers.each do |tracker|
        next unless tracker.entry_price.present? && tracker.quantity.present?

        ltp = get_paper_ltp(tracker)
        unless ltp
          Rails.logger.debug { "[RiskManager] No LTP for paper tracker #{tracker.order_no}" }
          next
        end

        entry = BigDecimal(tracker.entry_price.to_s)
        exit_price = BigDecimal(ltp.to_s)
        qty = tracker.quantity.to_i
        pnl = (exit_price - entry) * qty
        pnl_pct = entry.positive? ? ((exit_price - entry) / entry) : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct ? (pnl_pct * 100).round(2) : nil,
          high_water_mark_pnl: hwm
        )

        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] update_paper_positions_pnl failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end

      Rails.logger.info('[RiskManager] Paper PnL update completed')
    end

    # Ensure every active PositionTracker has an entry in Redis PnL cache (best-effort)
    # Throttled to avoid excessive queries - only runs every 5 seconds
    def ensure_all_positions_in_redis
      @last_ensure_all ||= Time.zone.at(0)
      return if Time.current - @last_ensure_all < 5.seconds

      trackers = PositionTracker.active.includes(:instrument).to_a
      return if trackers.empty?

      @last_ensure_all = Time.current

      positions = fetch_positions_indexed

      trackers.each do |tracker|
        redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
        next if redis_pnl && (Time.current.to_i - (redis_pnl[:timestamp] || 0)) < 10

        position = positions[tracker.security_id.to_s]
        tracker.hydrate_pnl_from_cache!

        ltp = if tracker.paper?
                get_paper_ltp(tracker)
              else
                current_ltp(tracker, position)
              end

        next unless ltp

        pnl = compute_pnl(tracker, position, ltp)
        next unless pnl

        pnl_pct = compute_pnl_pct(tracker, ltp, position)
        update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] ensure_all_positions_in_redis failed for #{tracker.order_no}: #{e.class} - #{e.message}")
      end
    end

    # Compute current LTP (will try cache, API, tradable, etc.)
    def current_ltp(tracker, position = nil)
      return get_paper_ltp(tracker) if tracker.paper?

      if position.respond_to?(:exchange_segment) && position.exchange_segment == 'NSE_FNO'
        begin
          response = DhanHQ::Models::MarketFeed.ltp({ 'NSE_FNO' => [tracker.security_id.to_i] })
          if response['status'] == 'success'
            option_data = response.dig('data', 'NSE_FNO', tracker.security_id.to_s)
            if option_data && option_data['last_price']
              ltp = BigDecimal(option_data['last_price'].to_s)
              begin
                Live::RedisPnlCache.instance.store_tick(segment: 'NSE_FNO', security_id: tracker.security_id, ltp: ltp,
                                                        timestamp: Time.current)
              rescue StandardError
                nil
              end
              return ltp
            end
          end
        rescue StandardError => e
          Rails.logger.error("[RiskManager] current_ltp(fetch option) failed for #{tracker.order_no}: #{e.class} - #{e.message}")
        end
      end

      tradable = tracker.tradable
      return tradable.ltp if tradable && tradable.ltp

      segment = tracker.segment.presence || tracker.instrument&.exchange_segment
      cached = Live::TickCache.ltp(segment, tracker.security_id)
      return BigDecimal(cached.to_s) if cached

      fetch_ltp(position, tracker)
    end

    def get_paper_ltp(tracker)
      segment = tracker.segment.presence || tracker.watchable&.exchange_segment || tracker.instrument&.exchange_segment
      security_id = tracker.security_id
      return nil unless segment.present? && security_id.present?

      cached = Live::TickCache.ltp(segment, security_id)
      return BigDecimal(cached.to_s) if cached

      tick_data = begin
        Live::TickCache.fetch(segment, security_id)
      rescue StandardError
        nil
      end
      return BigDecimal(tick_data[:ltp].to_s) if tick_data&.dig(:ltp)

      tradable = tracker.tradable
      if tradable
        ltp = begin
          tradable.fetch_ltp_from_api_for_segment(segment: segment, security_id: security_id)
        rescue StandardError
          nil
        end
        return BigDecimal(ltp.to_s) if ltp
      end

      begin
        response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
        if response['status'] == 'success'
          option_data = response.dig('data', segment, security_id.to_s)
          return BigDecimal(option_data['last_price'].to_s) if option_data && option_data['last_price']
        end
      rescue StandardError => e
        Rails.logger.error("[RiskManager] get_paper_ltp API error for #{tracker.order_no}: #{e.class} - #{e.message}")
      end

      nil
    end

    def fetch_ltp(position, tracker)
      segment = if position.respond_to?(:exchange_segment) then position.exchange_segment
                elsif position.is_a?(Hash) then position[:exchange_segment]
                end
      segment ||= tracker.instrument&.exchange_segment
      cached = begin
        Live::TickCache.ltp(segment, tracker.security_id)
      rescue StandardError
        nil
      end
      return BigDecimal(cached.to_s) if cached

      nil
    end

    def compute_pnl(tracker, position, ltp)
      if position.respond_to?(:net_qty) && position.respond_to?(:cost_price)
        quantity = position.net_qty.to_i
        cost_price = position.cost_price.to_f
        return nil if quantity.zero? || cost_price.zero?

        (ltp - BigDecimal(cost_price.to_s)) * quantity
      else
        quantity = tracker.quantity.to_i
        if quantity.zero? && position
          quantity = position.respond_to?(:quantity) ? position.quantity.to_i : (position[:quantity] || 0).to_i
        end
        return nil if quantity.zero?

        entry_price = tracker.entry_price || tracker.avg_price
        return nil if entry_price.blank?

        (ltp - BigDecimal(entry_price.to_s)) * quantity
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] compute_pnl failed for #{tracker.id}: #{e.class} - #{e.message}")
      nil
    end

    def compute_pnl_pct(tracker, ltp, position = nil)
      if position&.respond_to?(:cost_price)
        cost_price = position.cost_price.to_f
        return nil if cost_price.zero?

        (ltp - BigDecimal(cost_price.to_s)) / BigDecimal(cost_price.to_s)
      else
        entry_price = tracker.entry_price || tracker.avg_price
        return nil if entry_price.blank?

        (ltp - BigDecimal(entry_price.to_s)) / BigDecimal(entry_price.to_s)
      end
    rescue StandardError
      nil
    end

    def update_pnl_in_redis(tracker, pnl, pnl_pct, ltp)
      return unless pnl && ltp && ltp.to_f.positive?

      Live::PnlUpdaterService.instance.cache_intermediate_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pnl_pct,
        ltp: ltp,
        hwm: tracker.high_water_mark_pnl
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] update_pnl_in_redis failed for #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    # --- Internal exit logic (fallback when no external ExitEngine provided) ---
    # Attempts to exit a tracker:
    # - For paper: update DB fields and return success
    # - For live: try Orders gateway (Orders.config.flat_position) or DhanHQ position methods
    def exit_position(_position, tracker)
      if tracker.paper?
        current_ltp_value = get_paper_ltp(tracker)
        unless current_ltp_value
          Rails.logger.warn("[RiskManager] Cannot get LTP for paper exit #{tracker.order_no}")
          return { success: false, exit_price: nil }
        end

        exit_price = BigDecimal(current_ltp_value.to_s)
        entry = begin
          BigDecimal(tracker.entry_price.to_s)
        rescue StandardError
          nil
        end
        qty = tracker.quantity.to_i
        pnl = entry ? (exit_price - entry) * qty : nil
        pnl_pct = entry ? ((exit_price - entry) / entry) * 100 : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max if pnl

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct,
          high_water_mark_pnl: hwm,
          avg_price: exit_price
        )

        Rails.logger.info("[RiskManager] Paper exit simulated for #{tracker.order_no}: exit_price=#{exit_price}")
        return { success: true, exit_price: exit_price }
      end

      # Live exit flow: try Orders.config flat_position (recommended) -> DhanHQ SDK fallbacks
      begin
        segment = tracker.segment.presence || tracker.tradable&.exchange_segment || tracker.instrument&.exchange_segment
        unless segment.present?
          Rails.logger.error("[RiskManager] Cannot exit #{tracker.order_no}: no segment available")
          return { success: false, exit_price: nil }
        end

        if defined?(Orders) && Orders.respond_to?(:config) && Orders.config.respond_to?(:flat_position)
          order = Orders.config.flat_position(segment: segment, security_id: tracker.security_id)
          if order
            exit_price = current_ltp(tracker)
            exit_price = BigDecimal(exit_price.to_s) if exit_price
            return { success: true, exit_price: exit_price }
          end
        end

        # Fallback: try DhanHQ position convenience methods
        positions = fetch_positions_indexed
        position = positions[tracker.security_id.to_s]
        if position && position.respond_to?(:exit!)
          ok = position.exit!
          exit_price = begin
            current_ltp(tracker)
          rescue StandardError
            nil
          end
          return { success: ok, exit_price: exit_price }
        end

        Rails.logger.error("[RiskManager] Live exit failed for #{tracker.order_no} - no exit mechanism worked")
        { success: false, exit_price: nil }
      rescue StandardError => e
        Rails.logger.error("[RiskManager] exit_position error for #{tracker.order_no}: #{e.class} - #{e.message}")
        { success: false, exit_price: nil }
      end
    end

    # Persist reason metadata
    def store_exit_reason(tracker, reason)
      metadata = tracker.meta.is_a?(Hash) ? tracker.meta : {}
      tracker.update!(meta: metadata.merge('exit_reason' => reason, 'exit_triggered_at' => Time.current))
    rescue StandardError => e
      Rails.logger.warn("[RiskManager] store_exit_reason failed for #{tracker.order_no}: #{e.class} - #{e.message}")
    end

    def parse_time_hhmm(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError
      Rails.logger.warn("[RiskManager] Invalid time format provided: #{value}")
      nil
    end

    def risk_config
      raw = begin
        AlgoConfig.fetch[:risk]
      rescue StandardError
        {}
      end
      return {} if raw.blank?

      cfg = raw.dup
      cfg[:stop_loss_pct] = raw[:stop_loss_pct] || raw[:sl_pct]
      cfg[:take_profit_pct] = raw[:take_profit_pct] || raw[:tp_pct]
      cfg[:sl_pct] = cfg[:stop_loss_pct]
      cfg[:tp_pct] = cfg[:take_profit_pct]
      cfg[:breakeven_after_gain] = raw.key?(:breakeven_after_gain) ? raw[:breakeven_after_gain] : 0
      cfg[:trail_step_pct] = raw[:trail_step_pct] if raw.key?(:trail_step_pct)
      cfg[:exit_drop_pct] = raw[:exit_drop_pct] if raw.key?(:exit_drop_pct)
      cfg[:time_exit_hhmm] = raw[:time_exit_hhmm] if raw.key?(:time_exit_hhmm)
      cfg[:market_close_hhmm] = raw[:market_close_hhmm] if raw.key?(:market_close_hhmm)
      cfg[:min_profit_rupees] = raw[:min_profit_rupees] if raw.key?(:min_profit_rupees)
      cfg
    rescue StandardError => e
      Rails.logger.error("[RiskManager] risk_config error: #{e.class} - #{e.message}")
      {}
    end

    def cancel_remote_order(order_id)
      order = DhanHQ::Models::Order.find(order_id)
      order.cancel
    rescue DhanHQ::Error => e
      Rails.logger.error("[RiskManager] cancel_remote_order DhanHQ error: #{e.message}")
      raise
    rescue StandardError => e
      Rails.logger.error("[RiskManager] cancel_remote_order unexpected error: #{e.class} - #{e.message}")
      raise
    end

    def pct_value(value)
      BigDecimal(value.to_s)
    rescue StandardError
      BigDecimal(0)
    end
  end
end
