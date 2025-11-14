module Live
  class ExitEngine
    def initialize(order_router:)
      @router = order_router
    end

    def execute_exit(tracker, reason)
      price = Live::TickCache.ltp(tracker.segment, tracker.security_id)
      @router.exit_market(tracker)
      tracker.mark_exited!(exit_reason: reason, exit_price: price)
    end
  end
end
