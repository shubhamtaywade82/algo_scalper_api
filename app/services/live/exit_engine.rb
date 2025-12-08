# frozen_string_literal: true

module Live
  class ExitEngine
    def initialize(order_router:)
      @router = order_router
      @running = false
      @thread = nil
      @lock = Mutex.new
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

        # Use Command Pattern for exit with audit trail
        exit_command = Commands::ExitPositionCommand.new(
          tracker: tracker,
          exit_reason: reason,
          exit_price: safe_ltp(tracker),
          metadata: { triggered_by: 'exit_engine' }
        )

        result = exit_command.execute
        if result[:success]
          Rails.logger.info("[ExitEngine] Exit executed #{tracker.order_no}: #{reason}")
        else
          Rails.logger.error("[ExitEngine] Exit command failed for #{tracker.order_no}: #{result[:error]}")
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
