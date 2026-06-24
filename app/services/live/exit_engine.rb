# frozen_string_literal: true

require 'digest'

module Live
  class ExitEngine
    EXIT_INTENT_RETRY_AFTER_SECONDS = 15

    def initialize(order_router:)
      @router = order_router
      @running = false
      @lock = Mutex.new
    end

    # ExitEngine DOES NOT call risk logic.
    # It only exists to process exit requests when invoked by RiskManagerService.
    def start
      @lock.synchronize do
        return if @running

        @running = true
        # No background thread needed - execute_exit is called directly by RiskManagerService
      end
    end

    def stop
      @lock.synchronize do
        @running = false
      end
    end

    def running?
      @running
    end

    # Called by RiskManagerService when it delegates the exit to the engine.
    # ExitEngine is authoritative for placing router exit orders, then marking trackers exited.
    #
    # @param tracker [PositionTracker] The position tracker to exit
    # @param reason [String] The reason for the exit (e.g., 'stop_loss', 'take_profit', 'trailing_stop')
    # @param operator_retry [Boolean] When true (dashboard manual close only), bypass the
    #   "fresh exit intent" short-circuit if no broker ack yet so the operator can resubmit.
    # @return [Hash] Result hash with keys:
    #   - :success [Boolean] Whether the exit was successful
    #   - :reason [String] Reason code ('success', 'already_exited', 'invalid_tracker', etc.)
    #   - :exit_price [BigDecimal, nil] The exit price if successful
    #   - :error [Object, nil] Error details if router failed
    def execute_exit(tracker, reason, operator_retry: false)
      # Input validation
      return { success: false, reason: 'invalid_tracker' } unless tracker
      return { success: false, reason: 'invalid_router' } unless @router
      return { success: false, reason: 'invalid_reason' } if reason.blank?

      tracker.reload
      return { success: true, reason: 'already_exited', exit_price: tracker.exit_price } if tracker.exited?

      # State validation
      return { success: false, reason: 'not_active' } unless tracker.active?

      # Acquire process-wide exit lock to avoid dual intent (per-tick vs 5s loop)
      unless acquire_exit_lock(tracker.id)
        Rails.logger.info("[ExitEngine] Exit lock already held for #{tracker.order_no}, skipping duplicate exit request.")
        return { success: false, reason: 'exit_lock_held' }
      end

      begin
        intent_persisted = prepare_exit_intent!(tracker, reason, operator_retry: operator_retry)
        return { success: true, reason: 'already_exited', exit_price: tracker.exit_price } if tracker.exited?
        return { success: true, reason: 'exit_already_requested', client_order_id: tracker.exit_coid } unless intent_persisted

        ltp = safe_ltp(tracker)

        cmd_result = nil
        begin
          cmd_result = Orders::Commands::ExitOrderCommand.new(
            gateway: @router,
            tracker: tracker,
            client_order_id: tracker.exit_coid,
            reason: reason
          ).call
        rescue StandardError => e
          Rails.logger.error("[ExitEngine] Router exception for #{tracker.order_no}: #{e.class} - #{e.message}")
          return { success: false, reason: 'router_failed', error: e }
        end

        unless cmd_result.success?
          error_detail = cmd_result.error
          if error_detail.nil? && cmd_result.payload.is_a?(Hash)
            # Keep payload shape (includes :raw) for consistent caller/logging handling.
            error_detail = cmd_result.payload
          end
          error_detail = cmd_result.payload if error_detail.nil?

          Rails.logger.error("[ExitEngine] Router failed for #{tracker.order_no}: #{cmd_result.reason} (coid: #{tracker.exit_coid})")
          return { success: false, reason: 'router_failed', error: error_detail }
        end

        # Extract raw broker response from command payload for downstream helpers
        result = cmd_result.payload[:raw] || {}
        persist_broker_ack!(tracker, result)

        # Use exit_price from command payload if available, fallback to LTP
        exit_price = cmd_result.payload[:exit_price] || ltp

        finalize_exit!(tracker, exit_price: exit_price, reason: reason)
      rescue StandardError => e
        Rails.logger.error("[ExitEngine] Failed executing exit for #{tracker&.order_no}: #{e.class} - #{e.message} (coid: #{tracker&.exit_coid})")
        raise
      ensure
        release_exit_lock(tracker.id)
      end
    end

    private

    # Writes a durable exit intent before placing broker order.
    # @param tracker [PositionTracker]
    # @param reason [String]
    # @return [Boolean] true when a new intent was persisted, false when already requested/exited
    def prepare_exit_intent!(tracker, reason, operator_retry: false)
      tracker.with_lock do
        tracker.reload
        return false if tracker.exited?
        if tracker.exit_sent_at.present? && !operator_may_resubmit_active_exit?(tracker, operator_retry)
          return false
        end

        if !operator_retry && tracker.exit_requested_at.present? && !stale_exit_intent?(tracker)
          return false
        end

        if operator_retry && tracker.exit_requested_at.present? && !stale_exit_intent?(tracker)
          Rails.logger.info(
            "[ExitEngine] Operator manual close retry for #{tracker.order_no} " \
            '(re-invoking broker; exit_sent_at still blank)'
          )
        end

        coid = tracker.exit_coid.presence || deterministic_exit_coid(tracker)
        metadata = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}

        metadata['exit_reason'] = reason
        metadata['exit_triggered_at'] = Time.current

        snapshot = safe_pnl_snapshot(tracker)
        decision_pnl_pct = if snapshot && snapshot[:pnl_pct]
                             (snapshot[:pnl_pct].to_f * 100.0).round(2)
                           end

        decision_meta = (metadata['decision'].is_a?(Hash) ? metadata['decision'].dup : {})
        decision_meta['type'] = reason.to_s
        decision_meta['path'] ||= 'unknown'
        decision_meta['decided_at'] = Time.current.iso8601
        decision_meta['pnl_pct_at_decision'] = decision_pnl_pct if decision_pnl_pct
        metadata['decision'] = decision_meta

        tracker.update!(
          exit_requested_at: Time.current,
          exit_coid: coid,
          meta: metadata
        )
      end

      true
    end

    # Persists broker acknowledgement metadata after successful exit order placement.
    # @param tracker [PositionTracker]
    # @param result [Hash, Object]
    # @return [void]
    def persist_broker_ack!(tracker, result)
      order_id = result.is_a?(Hash) ? (result[:order_id] || result['order_id']) : nil
      tracker.update_columns( # rubocop:disable Rails/SkipsModelValidations
        exit_sent_at: Time.current,
        exit_order_id: order_id,
        updated_at: Time.current
      )
    end

    # Finalizes tracker state and notifications once broker accepts exit order.
    # @param tracker [PositionTracker]
    # @param exit_price [BigDecimal, Float, nil]
    # @param reason [String]
    # @return [Hash]
    def finalize_exit!(tracker, exit_price:, reason:)
      tracker.reload
      tracker.with_lock do
        tracker.reload
        return { success: true, exit_price: tracker.exit_price, reason: tracker.exit_reason || reason } if tracker.exited?

        tracker.mark_exited!(
          exit_price: exit_price,
          exit_reason: reason
        )
      end

      tracker.reload
      normalized_reason = normalize_exit_reason_with_final_pnl(tracker, reason)

      Rails.logger.info("[ExitEngine] Exit executed #{tracker.order_no}: #{normalized_reason} (coid: #{tracker.exit_coid})")

      Core::EventBus.instance.publish(Core::EventBus::EVENTS[:exit_triggered], {
        tracker_id: tracker.id,
        order_no: tracker.order_no,
        reason: normalized_reason,
        exit_price: exit_price,
        index_key: tracker.meta&.dig('index_key') || tracker.index_key
      })

      record_trade_telemetry(tracker, exit_price, normalized_reason)
      notify_telegram_exit(tracker, normalized_reason, exit_price)

      { success: true, exit_price: exit_price, reason: normalized_reason, client_order_id: tracker.exit_coid }
    rescue StandardError => e
      tracker.reload
      if tracker.exited?
        Rails.logger.info("[ExitEngine] Tracker already exited (likely by OrderUpdateHandler): #{tracker.order_no}")
        { success: true, exit_price: tracker.exit_price, reason: tracker.exit_reason || reason, client_order_id: tracker.exit_coid }
      else
        Rails.logger.error("[ExitEngine] Order placed but tracker update failed: #{tracker.order_no}: #{e.class} - #{e.message}")
        raise
      end
    end

    # Ensures displayed exit reason reflects final net PnL percentage.
    # @param tracker [PositionTracker]
    # @param reason [String]
    # @return [String]
    def normalize_exit_reason_with_final_pnl(tracker, reason)
      snapshot = final_pnl_snapshot(tracker)
      final_pnl = snapshot[:pnl]
      pnl_pct_decimal = snapshot[:pnl_pct_decimal]

      unless final_pnl.present? && pnl_pct_decimal
        Rails.logger.warn(
          "[ExitEngine] Cannot update exit reason for #{tracker.order_no}: " \
          "final_pnl=#{final_pnl.inspect}, pnl_pct=#{pnl_pct_decimal.inspect}, reason=#{reason.inspect}"
        )
        ensure_exit_reason_on_meta!(tracker, reason)
        return reason
      end

      classification = classify_exit(pnl_pct_decimal)

      tracker.transaction do
        tracker.lock!
        meta = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}

        execution_meta = (meta['execution'].is_a?(Hash) ? meta['execution'].dup : {})
        execution_meta['type'] = reason.to_s
        execution_meta['final_pnl_pct'] = pnl_pct_decimal.round(2)
        execution_meta['classified_as'] = classification
        meta['execution'] = execution_meta

        tracker.update!(meta: meta, exit_reason: build_final_reason(reason, execution_meta))
      end

      tracker.exit_reason
    end

    def ensure_exit_reason_on_meta!(tracker, reason)
      return if reason.blank?

      tracker.reload
      return if tracker.exit_reason.to_s.strip.present?

      col = reason.to_s
      tracker.update!(exit_reason: col)
    rescue StandardError => e
      Rails.logger.warn("[ExitEngine] ensure_exit_reason_on_meta! failed for #{tracker&.order_no}: #{e.class} - #{e.message}")
    end

    def final_pnl_snapshot(tracker)
      priced = Positions::FinalPnl.from_exit_price(
        entry_price: tracker.entry_price,
        quantity: tracker.quantity,
        exit_price: tracker.exit_price,
        is_exited: true
      )
      if priced
        return {
          pnl: priced[:pnl],
          pnl_pct_decimal: (priced[:pnl_pct].to_f * 100.0)
        }
      end

      final_pnl = tracker.last_pnl_rupees
      entry_price = tracker.entry_price
      quantity = tracker.quantity
      return { pnl: nil, pnl_pct_decimal: nil } unless final_pnl.present? && entry_price.present? &&
                                                       quantity.present? &&
                                                       entry_price.to_f.positive? && quantity.to_i.positive?

      {
        pnl: final_pnl,
        pnl_pct_decimal: (final_pnl.to_f / (entry_price.to_f * quantity.to_i)) * 100.0
      }
    end

    def classify_exit(final_pnl_pct_decimal)
      return 'profit' if final_pnl_pct_decimal.positive?
      return 'loss' if final_pnl_pct_decimal.negative?

      'breakeven'
    end

    def build_final_reason(reason, execution_meta)
      final_pct = execution_meta['final_pnl_pct']
      classification = execution_meta['classified_as']
      return reason unless final_pct && classification

      "#{reason} (Final: #{final_pct.round(2)}%, #{classification})"
    end

    def acquire_exit_lock(tracker_id, ttl: 10)
      key = "exit_lock:#{tracker_id}"
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      @redis.set(key, '1', nx: true, ex: ttl)
    rescue StandardError => e
      Rails.logger.error("[ExitEngine] acquire_exit_lock failed for tracker=#{tracker_id}: #{e.class} - #{e.message}")
      true
    end

    # Releases Redis exit lock immediately so the next close/exits are not blocked for the TTL window.
    def release_exit_lock(tracker_id)
      return if tracker_id.blank?
      return unless @redis

      @redis.del("exit_lock:#{tracker_id}")
    rescue StandardError => e
      Rails.logger.warn("[ExitEngine] release_exit_lock failed tracker=#{tracker_id}: #{e.class} - #{e.message}")
    end

    def stale_exit_intent?(tracker)
      return false if tracker.exit_requested_at.blank?

      (Time.current - tracker.exit_requested_at) >= EXIT_INTENT_RETRY_AFTER_SECONDS
    end

    # Broker ack persisted (exit_sent_at) but tracker still active — dashboard manual
    # close may resubmit; COID idempotency avoids duplicate live risk where supported.
    def operator_may_resubmit_active_exit?(tracker, operator_retry)
      operator_retry && tracker.active?
    end

    def safe_pnl_snapshot(tracker)
      Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
    rescue StandardError
      nil
    end

    # Generates a deterministic, broker-safe correlation id for exits.
    # @param tracker [PositionTracker]
    # @return [String]
    def deterministic_exit_coid(tracker)
      seed = "exit-#{tracker.id}-#{tracker.order_no}-#{tracker.security_id}"
      "AS-EXIT-#{Digest::SHA256.hexdigest(seed)[0, 20]}"
    end

    # Resolve LTP via the market-data query boundary
    def safe_ltp(tracker)
      Live::TickQuery.ltp_for(tracker)
    rescue StandardError
      nil
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
      Rails.logger.error("[ExitEngine] Telegram notification failed: #{e.class} - #{e.message}")
    end

    def record_trade_telemetry(tracker, exit_price, reason)
      return unless tracker&.exited?
      return if TradeTelemetry.exists?(tracker_id: tracker.id)

      entry_risk_rupees = tracker.meta&.dig('entry_risk_rupees')
      return if entry_risk_rupees.nil?

      entry_risk = BigDecimal(entry_risk_rupees.to_s)
      return unless entry_risk.positive?

      final_pnl = tracker.last_pnl_rupees
      max_pnl = tracker.high_water_mark_pnl

      exit_r = final_pnl ? (BigDecimal(final_pnl.to_s) / entry_risk) : nil
      max_r = max_pnl ? (BigDecimal(max_pnl.to_s) / entry_risk) : nil

      TradeTelemetry.create!(
        tracker_id: tracker.id,
        index_key: tracker.meta&.dig('index_key') || tracker.index_key,
        entry_time: tracker.created_at,
        exit_time: tracker.exited_at || Time.current,
        entry_tf: resolved_entry_tf(tracker),
        htf_tf: tracker.meta&.dig('htf_tf') || '15m', # Default to 15m if missing
        bos_age_at_entry: tracker.meta&.dig('bos_age_at_entry'),
        retrace_pct: tracker.meta&.dig('retrace_pct'),
        pullback_candles: tracker.meta&.dig('pullback_candles'),
        entry_distance_r: tracker.meta&.dig('entry_distance_r'),
        continuation_body_position: tracker.meta&.dig('continuation_body_position'),
        time_from_bos_to_entry: tracker.meta&.dig('time_from_bos_to_entry'),
        max_r_reached: max_r&.round(3),
        exit_r: exit_r&.round(3),
        exit_path: tracker.meta&.dig('exit_path') || reason,
        pnl_rupees: final_pnl,
        trade_state_at_exit: tracker.trade_state
      )
    rescue StandardError => e
      Rails.logger.error("[ExitEngine] Failed to record trade telemetry for #{tracker&.order_no}: #{e.class} - #{e.message}")
    end

    def resolved_entry_tf(tracker)
      tf = tracker.meta&.dig('entry_tf') || tracker.meta&.dig('timeframe')
      return tf if tf.present?

      '1m'
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
  end
end
