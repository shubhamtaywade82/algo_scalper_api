# frozen_string_literal: true

module Live
  class ExitEngine
    def initialize(order_router:)
      @router = order_router
      @running = false
      @thread = nil
      @lock = Mutex.new
      @risk_manager = Live::RiskManagerService.new(exit_engine: self)
    end

    # ExitEngine DOES NOT call risk logic.
    # It only exists to process exit requests when invoked by RiskManagerService.
    def start
      @lock.synchronize do
        return if @running

        @running = true

        @thread = Thread.new do
          Thread.current.name = 'exit-engine'
          loop do
            break unless @running

            begin
              # ExitEngine thread is idle - RiskManager calls execute_exit() directly
              # This thread exists for future use or monitoring
              sleep 0.5
            rescue StandardError => e
              Rails.logger.error("[ExitEngine] Thread error: #{e.class} - #{e.message}")
              Rails.logger.error("[ExitEngine] Backtrace: #{e.backtrace.first(5).join("\n")}")
            end
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
    # Primary method called by RiskManagerService
    def execute_exit(tracker, reason)
      tracker.with_lock do
        return if tracker.exited?

        ltp = safe_ltp(tracker)
        result = @router.exit_market(tracker)
        success = (result == true) ||
                  (result.is_a?(Hash) && result[:success] == true)

        if success
          tracker.mark_exited!(
            exit_price: ltp,
            exit_reason: reason
          )
          Rails.logger.info("[ExitEngine] Exit executed #{tracker.order_no}: #{reason}")
        else
          Rails.logger.error("[ExitEngine] Router failed for #{tracker.order_no}: #{result.inspect}")
        end
      end
    rescue StandardError => e
      Rails.logger.error("[ExitEngine] Failed executing exit for #{tracker.order_no}: #{e.class} - #{e.message}")
      raise
    end

    private

    # get LTP from cache or fallback
    def safe_ltp(tracker)
      if Live::TickCache.respond_to?(:ltp)
        Live::TickCache.ltp(tracker.segment, tracker.security_id)
      elsif Live::TickCache.respond_to?(:instance)
        Live::TickCache.ltp(tracker.segment, tracker.security_id)
      end
    rescue StandardError
      nil
    end
  end
end
