# frozen_string_literal: true

require 'bigdecimal'
require 'singleton'
require 'ostruct'
require_relative '../concerns/broker_fee_calculator'

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

    include Runner
    include ExitEnforcement
    include ExitExecution
    include PnlCache
    include Config

    def initialize(exit_engine: nil)
      @exit_engine = exit_engine
      @algo_config = begin
        AlgoConfig.fetch
      rescue StandardError
        {}
      end
      @paper_mode = @algo_config.dig(:paper_trading, :enabled) == true
      @orders_gateway = Orders.config ? Orders.config.gateway : Orders::GatewayFactory.build(paper_mode: @paper_mode)
      @active_cache = begin
        Positions::ActiveCache.instance
      rescue StandardError => e
        Rails.logger.error("[RiskManagerService] failed to initialize active_cache: #{e.class} - #{e.message}")
        nil
      end
      @mutex = Mutex.new
      @running = false
      @thread = nil
      @market_closed_checked = false # Track if we've already checked after market closed
      @watchdog_thread = nil # Initialize as nil, start watchdog only when service starts
    end

    # Start monitoring loop (non-blocking)
    def start
      # Check if thread is actually alive, not just if @running is true
      return if @running && @thread&.alive?

      @running = true

      # Start watchdog only when service is explicitly started
      start_watchdog unless @watchdog_thread&.alive?

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
            Notifications::TelegramNotifier.instance.notify_error("#{e.class} - #{e.message}", context: 'RiskManagerService#monitor_loop')
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
      @watchdog_thread&.kill
      @watchdog_thread = nil
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

      # Concurrency lock: don't process if this tracker is already being analyzed
      # in the main monitor_loop or another event thread.
      @active_enforcements ||= Concurrent::Map.new
      return if @active_enforcements[tracker_id]

      @active_enforcements[tracker_id] = true
      begin
        @last_realtime_tick_at = Time.current

        # Use ActivePositionsCache to avoid DB load in the high-frequency path
        tracker = Positions::ActivePositionsCache.instance.active_trackers.find { |t| t.id == tracker_id }
        return unless tracker&.active?

        # Evaluate immediate exits (Hard SL, TP, Trailing)
        # We use UnifiedExitChecker for sub-second logic
        exit_decision = Live::UnifiedExitChecker.check_exit_conditions(tracker)

        if exit_decision && exit_decision[:exit]
          reason = "#{exit_decision[:reason]} (Sub-second Trigger)"
          Rails.logger.info("[RiskManager] ⚡ HIGH-FREQUENCY EXIT for #{tracker.order_no}: #{reason}")

          # Execute exit immediately
          engine = @exit_engine || self
          dispatch_exit(engine, tracker, reason)
          return unless tracker.active?
        end

        # Portfolio-level profit lock evaluation
        begin
          Portfolio::PnlTracker.update_unrealized(
            tracker_id: tracker_id,
            pnl: event[:pnl].to_f
          )
          Portfolio::ProfitLockEngine.evaluate!
        rescue StandardError => e
          Rails.logger.error("[RiskManager] Portfolio::ProfitLockEngine error: #{e.class} - #{e.message}")
        end

        return unless realtime_tick_first_enabled?
        return unless should_run_realtime_enforcement?(tracker_id)

        # We need position_data for the rules
        position_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker_id)
        return unless position_data

        run_enforcement_for_tracker(tracker, @exit_engine || self, position_data: position_data)
      ensure
        @active_enforcements.delete(tracker_id)
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Event-driven evaluation failed for tracker=#{tracker_id}: #{e.class} - #{e.message}")
    end

    def should_run_realtime_enforcement?(tracker_id)
      gap = realtime_min_enforcement_gap_seconds
      return true if gap <= 0

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      last = @last_realtime_eval_at[tracker_id]

      if last.nil? || (now - last) >= gap
        @last_realtime_eval_at[tracker_id] = now
        true
      else
        false
      end
    end

    def compute_pnl_pct(tracker, ltp, position = nil)
      if position.respond_to?(:cost_price)
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
      return unless pnl && ltp&.to_f&.positive?

      Live::PnlUpdaterService.instance.cache_intermediate_pnl(
        tracker_id: tracker.id,
        pnl: pnl,
        pnl_pct: pnl_pct,
        ltp: ltp,
        hwm: tracker.high_water_mark_pnl
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManagerService] active_cache unavailable: #{e.class} - #{e.message}")
      nil
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
        gross_pnl = entry ? (exit_price - entry) * qty : nil

        # Deduct broker fees (₹20 per order, ₹40 per trade - position is being exited)
        pnl = gross_pnl ? BrokerFeeCalculator.net_pnl(gross_pnl, is_exited: true) : nil
        # Calculate pnl_pct as decimal (0.0573 for 5.73%) for consistent DB storage (matches Redis format)
        pnl_pct = entry ? ((exit_price - entry) / entry) : nil

        hwm = tracker.high_water_mark_pnl || BigDecimal(0)
        hwm = [hwm, pnl].max if pnl

        tracker.update!(
          last_pnl_rupees: pnl,
          last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil,
          high_water_mark_pnl: hwm,
          avg_price: exit_price
        )

        Rails.logger.info("[RiskManager] Paper exit simulated for #{tracker.order_no}: exit_price=#{exit_price}")
        return { success: true, exit_price: exit_price }
      end

      # Live exit flow: try Orders.config flat_position (recommended) -> DhanHQ SDK fallbacks
      begin
        segment = tracker.segment.presence || tracker.tradable&.exchange_segment || tracker.instrument&.exchange_segment
        if segment.blank?
          Rails.logger.error("[RiskManager] Cannot exit #{tracker.order_no}: no segment available")
          return { success: false, exit_price: nil }
        end

      risk_level =
        case confidence
        when 0.8..1.0 then :low
        when 0.6...0.8 then :medium
        else :high
        end

        # Fallback: try DhanHQ position convenience methods
        positions = fetch_positions_indexed
        position = positions[tracker.security_id.to_s]
        if position.respond_to?(:exit!)
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

    # Send Telegram exit notification
    # @param tracker [PositionTracker] Position tracker
    # @param reason [String] Exit reason
    # @param exit_price [BigDecimal, Float, nil] Exit price
    def notify_telegram_exit(tracker, reason, exit_price)
      return unless telegram_enabled?

      # Reload tracker to get final PnL
      tracker.reload if tracker.respond_to?(:reload)
      pnl = tracker.last_pnl_rupees

      Notifications::TelegramNotifier.instance.notify_exit(
        tracker,
        exit_reason: reason,
        exit_price: exit_price,
        pnl: pnl
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Telegram notification failed: #{e.class} - #{e.message}")
    end

    # Check if Telegram notifications are enabled
    # @return [Boolean]
    def telegram_enabled?
      config = AlgoConfig.fetch[:telegram] || {}
      enabled = config[:enabled] != false && config[:notify_exit] != false
      enabled && Notifications::TelegramNotifier.instance.enabled?
    rescue StandardError
      false
    end

    def parse_time_hhmm(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError
      Rails.logger.warn("[RiskManager] Invalid time format provided: #{value}")
      nil
    end

    # Calculate seconds spent below entry price
    # Tracks this in Redis cache keyed by tracker_id
    def seconds_below_entry(tracker)
      cache_key = "position:below_entry:#{tracker.id}"
      cached = Rails.cache.read(cache_key)

      snapshot = pnl_snapshot(tracker)
      return 0 unless snapshot

      pnl_pct = snapshot[:pnl_pct]
      return 0 if pnl_pct.nil? || pnl_pct >= 0

      # If position is below entry, increment counter
      Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
      if cached
        # Update timestamp if still below entry
        (Time.current - cached).to_i
      else
        # First time below entry, initialize
        0
      end
    rescue StandardError => e
      Rails.logger.error("[RiskManager] seconds_below_entry error for #{tracker.id}: #{e.class} - #{e.message}")
      0
    end

    # Calculate ATR ratio (current ATR / recent ATR average)
    # Returns 1.0 if calculation fails (normal volatility)
    def calculate_atr_ratio(tracker)
      instrument = tracker.instrument || tracker.watchable&.instrument
      return 1.0 unless instrument

      # Try to get ATR from instrument's candle series
      begin
        series = instrument.candle_series(interval: '5') # 5-minute candles
        return 1.0 unless series&.candles&.any?

        candles = series.candles.last(20) # Last 20 candles
        return 1.0 if candles.size < 10

        # Calculate current ATR (last 14 periods)
        current_atr = calculate_atr(candles.last(14))
        return 1.0 unless current_atr.positive?

        # Calculate average ATR (last 20 periods)
        avg_atr = calculate_atr(candles)
        return 1.0 unless avg_atr.positive?

        ratio = current_atr / avg_atr
        ratio.round(3)
      rescue StandardError => e
        Rails.logger.debug { "[RiskManager] ATR ratio calculation failed for #{tracker.order_no}: #{e.message}" }
        1.0
      end
    end

    # Helper: Calculate ATR from candles
    def calculate_atr(candles)
      return 0.0 if candles.size < 2

      true_ranges = []
      candles.each_cons(2) do |prev, curr|
        tr1 = curr.high - curr.low
        tr2 = (curr.high - prev.close).abs
        tr3 = (curr.low - prev.close).abs
        true_ranges << [tr1, tr2, tr3].max
      end

      return 0.0 if true_ranges.empty?

      true_ranges.sum / true_ranges.size
    end

    # Build position data hash for Early Trend Failure checks
    def build_position_data_for_etf(tracker, _snapshot, instrument)
      # Get trend metrics from instrument
      series = begin
        instrument.candle_series(interval: '5')
      rescue StandardError
        nil
      end
      candles = series&.candles || []

      # Calculate ADX
      adx_value = begin
        instrument.adx(14, interval: '5')
      rescue StandardError
        nil
      end
      adx_hash = adx_value.is_a?(Hash) ? adx_value : { value: adx_value }

      # Calculate ATR ratio
      atr_ratio = calculate_atr_ratio(tracker)

      # Get underlying price (for VWAP check)
      underlying_price = current_ltp(tracker) || tracker.entry_price.to_f

      # Build trend score (simplified: use ADX + momentum)
      trend_score = if adx_hash[:value]
                      adx_hash[:value].to_f + (candles.any? ? momentum_score(candles) : 0)
                    else
                      0
                    end

      # Peak trend score (tracked in Redis or use current if no peak)
      peak_trend_score = tracker.meta&.dig('peak_trend_score') || trend_score
      if trend_score > peak_trend_score
        peak_trend_score = trend_score
        tracker.update(meta: (tracker.meta || {}).merge('peak_trend_score' => peak_trend_score))
      end

      # VWAP (simplified: use recent average price)
      vwap = candles.any? ? candles.last(20).sum(&:close) / candles.last(20).size : underlying_price

      OpenStruct.new(
        trend_score: trend_score,
        peak_trend_score: peak_trend_score,
        adx: adx_hash[:value],
        atr_ratio: atr_ratio,
        underlying_price: underlying_price,
        vwap: vwap,
        is_long?: %w[long_ce long_pe].include?(tracker.side)
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] build_position_data_for_etf error: #{e.class} - #{e.message}")
      OpenStruct.new(
        trend_score: 0,
        peak_trend_score: 0,
        adx: nil,
        atr_ratio: 1.0,
        underlying_price: tracker.entry_price.to_f,
        vwap: tracker.entry_price.to_f,
        is_long?: true
      )
    end

    # Calculate momentum score from candles (0-50 range)
    def momentum_score(candles)
      return 0 if candles.size < 3

      recent = candles.last(3)
      return 0 if recent.size < 2

      # Simple momentum: price change direction and magnitude
      price_change = (recent.last.close - recent.first.close) / recent.first.close
      volume_factor = if recent.last.respond_to?(:volume) && recent.last.volume
                        [recent.last.volume / 1_000_000.0,
                         1.0].min
                      else
                        0.5
                      end

      (price_change.abs * 100 * volume_factor).round(2)
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

    def hard_rupee_sl_enabled?
      cfg = hard_rupee_sl_config
      cfg && cfg[:enabled] == true
    end

    def hard_rupee_tp_enabled?
      cfg = hard_rupee_tp_config
      cfg && cfg[:enabled] == true
    end

    def hard_rupee_sl_config
      AlgoConfig.fetch.dig(:risk, :hard_rupee_sl)
    rescue StandardError
      nil
    end

    def hard_rupee_tp_config
      AlgoConfig.fetch.dig(:risk, :hard_rupee_tp)
    rescue StandardError
      nil
    end

    def post_profit_zone_enabled?
      cfg = post_profit_zone_config
      cfg && cfg[:enabled] != false
    end

    def post_profit_zone_config
      raw = begin
        AlgoConfig.fetch.dig(:risk, :post_profit_zone) || {}
      rescue StandardError
        {}
      end

      # Defaults
      {
        enabled: true,
        secured_profit_threshold_rupees: raw[:secured_profit_threshold_rupees] || 2000,
        runner_zone_threshold_rupees: raw[:runner_zone_threshold_rupees] || 4000,
        secured_sl_rupees: raw[:secured_sl_rupees] || 800,
        underlying_adx_min: raw[:underlying_adx_min] || 18.0,
        option_pullback_max_pct: raw[:option_pullback_max_pct] || 35.0,
        underlying_atr_collapse_threshold: raw[:underlying_atr_collapse_threshold] || 0.65,
        runner_zone_momentum_check: raw[:runner_zone_momentum_check] || false
      }.merge(raw)
    end

    def transition_to_secured_profit_zone(tracker, net_pnl_rupees, _target_profit_rupees)
      # Check if already transitioned
      return if tracker.meta&.dig('profit_zone_state') == 'secured_profit_zone'

      # Move SL to green (+₹500 to +₹1,000)
      secured_sl_config = post_profit_zone_config
      secured_sl_rupees = BigDecimal((secured_sl_config[:secured_sl_rupees] || 800).to_s)

      # Calculate entry price and quantity
      entry_price = tracker.entry_price
      quantity = tracker.quantity
      return unless entry_price && quantity&.positive?

      # Calculate SL price that gives us secured_sl_rupees profit
      # Formula: (sl_price - entry_price) * quantity - exit_fee = secured_sl_rupees
      # sl_price = entry_price + (secured_sl_rupees + exit_fee) / quantity
      exit_fee = BrokerFeeCalculator.fee_per_order
      sl_price = entry_price + (BigDecimal((secured_sl_rupees + exit_fee).to_s) / quantity)

      # Update tracker metadata
      meta = tracker.meta || {}
      meta = {} unless meta.is_a?(Hash)
      meta['profit_zone_state'] = 'secured_profit_zone'
      meta['secured_sl_price'] = sl_price.to_f
      meta['secured_sl_rupees'] = secured_sl_rupees.to_f
      meta['profit_zone_transitioned_at'] = Time.current.iso8601

      tracker.update_column(:meta, meta)

      Rails.logger.info(
        "[RiskManager] Transitioned #{tracker.order_no} to SECURED_PROFIT_ZONE " \
        "(PnL: ₹#{net_pnl_rupees.round(2)}, SL: ₹#{secured_sl_rupees}, SL Price: ₹#{sl_price.round(2)})"
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] transition_to_secured_profit_zone error: #{e.class} - #{e.message}")
    end

    def build_position_data_for_rule_engine(tracker, snapshot)
      # Build PositionData compatible with RuleContext
      instrument = tracker.instrument || tracker.watchable&.instrument
      index_key = tracker.meta&.dig('index_key') || instrument&.symbol_name

      Positions::ActiveCache::PositionData.new(
        tracker_id: tracker.id,
        security_id: tracker.security_id,
        segment: tracker.segment || instrument&.exchange_segment,
        entry_price: tracker.entry_price,
        quantity: tracker.quantity,
        current_ltp: snapshot[:ltp],
        pnl: snapshot[:pnl],
        pnl_pct: snapshot[:pnl_pct],
        high_water_mark: snapshot[:hwm_pnl],
        peak_profit_pct: calculate_peak_profit_pct(tracker, snapshot),
        position_direction: Positions::MetadataResolver.direction(tracker),
        index_key: index_key,
        underlying_segment: instrument&.exchange_segment,
        underlying_security_id: instrument&.security_id,
        underlying_symbol: index_key
      )
    end

    def calculate_peak_profit_pct(tracker, snapshot)
      hwm = snapshot[:hwm_pnl]
      return nil unless hwm&.positive?

      entry_price = tracker.entry_price
      quantity = tracker.quantity
      return nil unless entry_price && quantity&.positive?

      buy_value = entry_price * quantity
      return nil unless buy_value.positive?

      (hwm / buy_value).to_f
    end

    def iv_collapse_detection_enabled?
      config = begin
        AlgoConfig.fetch.dig(:risk, :time_overrides, :iv_collapse) || {}
      rescue StandardError
        {}
      end
      config[:enabled] == true
    end

    def stall_detection_enabled?
      config = stall_detection_config
      config[:enabled] == true
    end

    def stall_detection_config
      AlgoConfig.fetch.dig(:risk, :time_overrides, :stall_detection) || {}
    rescue StandardError
      {}
    end

    # Configuration helpers for new 5-layer exit system

    def structure_invalidation_enabled?
      config = AlgoConfig.fetch.dig(:risk, :exits, :structure_invalidation) || {}
      config.fetch(:enabled, true) # Default: enabled
    rescue StandardError
      true
    end

    def premium_momentum_failure_enabled?
      config = AlgoConfig.fetch.dig(:risk, :exits, :premium_momentum_failure) || {}
      config.fetch(:enabled, true) # Default: enabled
    rescue StandardError
      true
    end

    def time_stop_enabled?
      config = AlgoConfig.fetch.dig(:risk, :exits, :time_stop) || {}
      config.fetch(:enabled, true) # Default: enabled
    rescue StandardError
      true
    end

    # Record trade result in EdgeFailureDetector
    def record_trade_result_for_edge_detector(tracker, final_pnl, exit_reason)
      return unless tracker && final_pnl && exit_reason

      index_key = tracker.meta&.dig('index_key') || tracker.instrument&.symbol_name
      return unless index_key

      Live::EdgeFailureDetector.instance.record_trade_result(
        index_key: index_key,
        pnl_rupees: final_pnl.to_f,
        exit_reason: exit_reason.to_s,
        exit_time: Time.current
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] record_trade_result_for_edge_detector error: #{e.class} - #{e.message}")
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

      { risk_level: risk_level, max_position_size: max_position_size, recommended_stop_loss: recommended_stop_loss }
    end

    # Track exit path for analysis
    def track_exit_path(tracker, exit_path, reason)
      meta = tracker.meta || {}
      meta = {} unless meta.is_a?(Hash)

      direction = if exit_path.include?('upward')
                    'upward'
                  else
                    (exit_path.include?('downward') ? 'downward' : nil)
                  end
      type = if exit_path.include?('adaptive')
               'adaptive'
             else
               (exit_path.include?('fixed') ? 'fixed' : nil)
             end

      # Ensure entry metadata is preserved (in case it wasn't set during creation)
      # This is a safety net - entry metadata should already be set in EntryGuard
      entry_meta = {}
      unless meta['entry_path'] || meta['entry_strategy']
        # Try to find matching TradingSignal to get entry metadata
        signal = TradingSignal.where("metadata->>'index_key' = ?", meta['index_key'] || tracker.index_key)
                              .where(created_at: (tracker.created_at - 5.minutes)..)
                              .where(created_at: ..(tracker.created_at + 1.minute))
                              .order(created_at: :desc)
                              .first

        if signal && signal.metadata.is_a?(Hash)
          entry_meta['entry_path'] = signal.metadata['entry_path']
          entry_meta['entry_strategy'] = signal.metadata['strategy']
          entry_meta['entry_strategy_mode'] = signal.metadata['strategy_mode']
          entry_meta['entry_timeframe'] = signal.metadata['effective_timeframe'] || signal.metadata['primary_timeframe']
          entry_meta['entry_confirmation_timeframe'] = signal.metadata['confirmation_timeframe']
          entry_meta['entry_validation_mode'] = signal.metadata['validation_mode']
        end
      end

      tracker.update(
        meta: meta.merge(entry_meta).merge(
          'exit_path' => exit_path,
          'exit_reason' => reason,
          'exit_direction' => direction,
          'exit_type' => type,
          'exit_triggered_at' => Time.current
        )
      )
    rescue StandardError => e
      Rails.logger.error("[RiskManager] Failed to track exit path for #{tracker.order_no}: #{e.message}")
    end
  end
end
