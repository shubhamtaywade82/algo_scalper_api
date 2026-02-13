# frozen_string_literal: true

module Live
  class RiskManagerService
    module ExitExecution
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

            # Reload tracker to get final PnL values after mark_exited!
            tracker.reload

            # Update exit reason with final PnL percentage for consistency
            # Calculate PnL percentage from final PnL value (includes broker fees)
            # This matches what Telegram notifier will display
            final_pnl = tracker.last_pnl_rupees
            entry_price = tracker.entry_price
            quantity = tracker.quantity

            if final_pnl.present? && entry_price.present? && quantity.present? &&
               entry_price.to_f.positive? && quantity.to_i.positive? && reason.present? && reason.include?('%')
              # Calculate PnL percentage (includes fees) - matches Telegram display
              pnl_pct_display = ((final_pnl.to_f / (entry_price.to_f * quantity.to_i)) * 100.0).round(2)
              # Extract the base reason (e.g., "SL HIT" or "TP HIT") - everything before the percentage
              base_reason = reason.split(/\s+-?\d+\.?\d*%/).first&.strip || reason.split('%').first&.strip || reason
              updated_reason = "#{base_reason} #{pnl_pct_display}%"

              # Always update to ensure consistency (even if values are close)
              if reason != updated_reason
                Rails.logger.info("[RiskManager] Updating exit reason for #{tracker.order_no}: '#{reason}' -> '#{updated_reason}' (PnL: ₹#{final_pnl}, PnL%: #{pnl_pct_display}%)")
                # exit_reason is a store_accessor on meta, so update via meta hash
                meta = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}
                meta['exit_reason'] = updated_reason
                tracker.update_column(:meta, meta)
              end
            else
              Rails.logger.warn("[RiskManager] Cannot update exit reason for #{tracker.order_no}: final_pnl=#{final_pnl.inspect}, entry_price=#{entry_price.inspect}, quantity=#{quantity.inspect}, reason=#{reason.inspect}")
            end

            Rails.logger.info("[RiskManager] Successfully exited #{tracker.order_no} (#{tracker.id}) via internal executor")

            # Record trade result in EdgeFailureDetector (for edge failure detection)
            record_trade_result_for_edge_detector(tracker, final_pnl, final_reason || reason)

            # Send Telegram notification
            final_reason = updated_reason || reason
            notify_telegram_exit(tracker, final_reason, exit_price)

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

      private

      # Helper that centralizes exit dispatching logic.
      # If exit_engine is an object responding to execute_exit, delegate to it.
      # If exit_engine == self (or nil) we fallback to internal execute_exit implementation.
      def dispatch_exit(exit_engine, tracker, reason)
        if exit_engine.respond_to?(:execute_exit) && !exit_engine.equal?(self)
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
