# frozen_string_literal: true

module Live
  class ExitEngine
    def initialize(order_router:)
      @router = order_router
      @running = false
      @thread = nil
      @lock = Mutex.new
      @risk_manager = Live::RiskManagerService.new
    end

    def start
      @lock.synchronize do
        return if @running
        @running = true

        @thread = Thread.new do
          Thread.current.name = 'exit-engine'
          loop do
            break unless @running
            begin
              # Let RiskManager fetch positions itself. Pass the engine via keyword.
              @risk_manager.enforce_hard_limits(exit_engine: self)
              @risk_manager.enforce_trailing_stops(exit_engine: self)
              @risk_manager.enforce_time_based_exit(exit_engine: self)
            rescue StandardError => e
              Rails.logger.error("[ExitEngine] crash: #{e.class} - #{e.message}\n#{e.backtrace.first(6).join("\n")}")
            end
            sleep 1
          end
        end
      end
    end


    def stop
      @lock.synchronize do
        return unless @running
        @running = false
      end

      @thread&.kill
      @thread&.join(1)
    end

    # Called by RiskManagerService when it delegates the exit to the engine.
    # ExitEngine is authoritative for placing router exit orders, then marking trackers exited.
    def execute_exit(tracker, reason)
      begin
        ltp = begin
          # Prefer TickCache class method if available
          if Live::TickCache.respond_to?(:ltp)
            Live::TickCache.ltp(tracker.segment, tracker.security_id)
          elsif Live::TickCache.respond_to?(:instance) && Live::TickCache.instance.respond_to?(:ltp)
            Live::TickCache.instance.ltp(tracker.segment, tracker.security_id)
          end
        rescue StandardError
          nil
        end

        # Ask router to place/flatten position. router must be synchronous or return success indicator.
        # Router API expected: exit_market(tracker) -> true/false or raise on failure.
        result = @router.exit_market(tracker)
        success = result == true || result.is_a?(Hash) && result[:success] == true

        if success
          # Persist exit via tracker's mark_exited!, include reason and exit_price (if available).
          tracker.mark_exited!(exit_price: ltp, exit_reason: reason)
          Rails.logger.info("[ExitEngine] Executed exit for #{tracker.order_no}: #{reason}")
        else
          Rails.logger.error("[ExitEngine] Router failed to exit #{tracker.order_no}: #{result.inspect}")
        end
      rescue StandardError => e
        Rails.logger.error("[ExitEngine] Failed to execute exit for #{tracker.order_no}: #{e.class} - #{e.message}")
        raise
      end
    end
  end
end
