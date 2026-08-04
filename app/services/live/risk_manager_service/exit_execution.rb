# frozen_string_literal: true

module Live
  class RiskManagerService
    module ExitExecution
      private

      # Helper that centralizes exit dispatching logic.
      # If exit_engine is an object responding to execute_exit, delegate to it.
      # RiskManagerService no longer supports self-managed fallback execution.
      def dispatch_exit(exit_engine, tracker, reason)
        if exit_engine.respond_to?(:execute_exit) && !exit_engine.equal?(self)
          exit_engine.execute_exit(tracker, reason)
        else
          Rails.logger.fatal(
            "[RiskManager] CRITICAL: ExitEngine unavailable for #{tracker.order_no} " \
              "(reason=#{reason}) — position NOT exited"
          )
          raise "ExitEngine unavailable for #{tracker.order_no}"
        end
      end

      # Persist reason metadata
      def store_exit_reason(tracker, reason)
        tracker.update!(
          exit_reason: reason,
          exit_triggered_at: Time.current
        )
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

      # Record trade result in EdgeFailureDetector
      def record_trade_result_for_edge_detector(tracker, final_pnl, exit_reason)
        return unless tracker && final_pnl && exit_reason

        index_key = tracker.index_key || tracker.instrument&.symbol_name
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
        @orders_gateway.cancel_order(order_id)
      rescue StandardError => e
        Rails.logger.error("[RiskManager] cancel_remote_order failed for #{order_id}: #{e.class} - #{e.message}")
        raise
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
end
