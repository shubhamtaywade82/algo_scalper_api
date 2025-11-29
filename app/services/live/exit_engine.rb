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
            tracker.mark_exited!(
              exit_price: ltp,
              exit_reason: reason
            )
            Rails.logger.info("[ExitEngine] Exit executed #{tracker.order_no}: #{reason}")
            return { success: true, exit_price: ltp, reason: reason }
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
  end
end
