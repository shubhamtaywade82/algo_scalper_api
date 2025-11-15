module TradingSystem
  class OrderRouter < BaseService
    RETRY_COUNT = 3
    RETRY_BASE_SLEEP = 0.2

    def initialize(gateway: Orders.config.gateway)
      @gateway = gateway
    end

     # Required by BaseService (Supervisor calls start/stop)
     def start
      Rails.logger.info("[OrderRouter] ready (no-op)")
      true
    end

    def stop
      Rails.logger.info("[OrderRouter] stopped (no-op)")
      true
    end


    def exit_market(tracker)
      with_retries do
        @gateway.exit_market(tracker)
      end
    rescue StandardError => e
      Rails.logger.error("[OrderRouter] exit_market exception for #{tracker.order_no}: #{e.class} - #{e.message}")
      { success: false, error: e.message }
    end

    private

    def with_retries
      attempts = 0
      begin
        attempts += 1
        yield
      rescue StandardError => e
        raise if attempts >= RETRY_COUNT

        sleep RETRY_BASE_SLEEP * attempts
        retry
      end
    end
  end
end
