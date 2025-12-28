# frozen_string_literal: true

module Live
  class ExitEngine
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
    # @return [Hash] Result hash with keys:
    #   - :success [Boolean] Whether the exit was successful
    #   - :reason [String] Reason code ('success', 'already_exited', 'invalid_tracker', etc.)
    #   - :exit_price [BigDecimal, nil] The exit price if successful
    #   - :error [Object, nil] Error details if router failed
    def execute_exit(tracker, reason)
      # Input validation
      return { success: false, reason: 'invalid_tracker' } unless tracker
      return { success: false, reason: 'invalid_router' } unless @router
      return { success: false, reason: 'invalid_reason' } if reason.blank?

      # State validation
      return { success: false, reason: 'not_active' } unless tracker.active?

      tracker.with_lock do
        # Early return if already exited (idempotent - not an error)
        return { success: true, reason: 'already_exited', exit_price: tracker.exit_price } if tracker.exited?

        ltp = safe_ltp(tracker)
        result = @router.exit_market(tracker)
        success = success?(result)

        if success
          begin
            # Use exit_price from gateway if available (paper mode provides this), fallback to LTP
            # This ensures paper mode uses correct exit_price (LTP or entry_price fallback)
            # Live mode gateways don't provide exit_price, so we use LTP
            exit_price = (result.is_a?(Hash) && result[:exit_price]) || ltp

            tracker.mark_exited!(
              exit_price: exit_price,
              exit_reason: reason
            )

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
                Rails.logger.info("[ExitEngine] Updating exit reason for #{tracker.order_no}: '#{reason}' -> '#{updated_reason}' (PnL: ₹#{final_pnl}, PnL%: #{pnl_pct_display}%)")
                # exit_reason is a store_accessor on meta, so update via meta hash
                meta = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}
                meta['exit_reason'] = updated_reason
                tracker.update_column(:meta, meta)
                reason = updated_reason
              end
            else
              Rails.logger.warn("[ExitEngine] Cannot update exit reason for #{tracker.order_no}: final_pnl=#{final_pnl.inspect}, entry_price=#{entry_price.inspect}, quantity=#{quantity.inspect}, reason=#{reason.inspect}")
            end

            Rails.logger.info("[ExitEngine] Exit executed #{tracker.order_no}: #{reason}")

            # Send Telegram notification
            notify_telegram_exit(tracker, reason, exit_price)

            return { success: true, exit_price: exit_price, reason: reason }
          rescue StandardError => e
            # Order is placed, but tracker update failed
            # Check if tracker is already exited (might have been updated by OrderUpdateHandler)
            tracker.reload
            if tracker.exited?
              Rails.logger.info("[ExitEngine] Tracker already exited (likely by OrderUpdateHandler): #{tracker.order_no}")
              return { success: true, exit_price: tracker.exit_price, reason: tracker.exit_reason || reason }
            else
              Rails.logger.error("[ExitEngine] Order placed but tracker update failed: #{tracker.order_no}: #{e.class} - #{e.message}")
              raise
            end
          end
        else
          Rails.logger.error("[ExitEngine] Router failed for #{tracker.order_no}: #{result.inspect}")
          return { success: false, reason: 'router_failed', error: result }
        end
      end
    rescue StandardError => e
      Rails.logger.error("[ExitEngine] Failed executing exit for #{tracker.order_no}: #{e.class} - #{e.message}")
      raise
    end

    private

    # Get LTP from cache with error handling
    # Since Live::TickCache.ltp always exists (delegates to ::TickCache.instance.ltp),
    # we can simplify to a direct call
    def safe_ltp(tracker)
      Live::TickCache.ltp(tracker.segment, tracker.security_id)
    rescue StandardError
      nil
    end

    # Determine if router result indicates success
    # Handles various return formats: boolean true, hash with success: true, hash with success: 1, etc.
    def success?(result)
      return true if result == true
      return false unless result.is_a?(Hash)

      success_value = result[:success]
      return true if success_value == true
      return true if success_value == 1
      return true if success_value.to_s.downcase == 'true'
      return true if success_value.to_s.downcase == 'yes'

      false
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
