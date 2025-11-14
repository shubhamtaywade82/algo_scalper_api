# frozen_string_literal: true

module Live
  class ExitEngine
    def initialize(order_router:)
      @router = order_router
      @running = false
      @thread = nil
      @lock = Mutex.new
    end

    # supervisor calls this
    def start
      @lock.synchronize do
        return if @running

        @running = true

        @thread = Thread.new do
          Thread.current.name = 'exit-engine'

          loop do
            Live::RiskManagerService.check_positions_for_exit(self)
            sleep 1
          end
        rescue StandardError => e
          Rails.logger.error("[ExitEngine] crash: #{e.class} - #{e.message}")
          sleep 2
          retry
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

    def execute_exit(tracker, reason)
      ltp = Live::TickCache.ltp(tracker.segment, tracker.security_id)
      @router.exit_market(tracker)
      tracker.mark_exited!(exit_reason: reason, exit_price: ltp)
    end
  end
end
