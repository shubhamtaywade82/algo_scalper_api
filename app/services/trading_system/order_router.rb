# frozen_string_literal: true

require 'timeout'

module TradingSystem
  class OrderRouter
    RETRY_COUNT = 3
    RETRY_BASE_SLEEP = 0.2
    RETRYABLE_ERROR_CLASSES = [Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT].freeze

    def initialize(gateway: Orders.config.gateway)
      @gateway = gateway
    end

    # Required by BaseService (Supervisor calls start/stop)
    def start
      Rails.logger.info('[OrderRouter] ready (no-op)')
      true
    end

    def stop
      Rails.logger.info('[OrderRouter] stopped (no-op)')
      true
    end

    # Routes exit requests to the configured gateway with retry handling.
    # @param tracker [PositionTracker]
    # @param client_order_id [String, nil]
    # @return [Hash]
    def exit_market(tracker, client_order_id: nil)
      with_retries do
        @gateway.exit_market(tracker, client_order_id: client_order_id)
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
        # Only retry errors where "the request may not have reached the broker" is
        # plausible. A definitive rejection (bad params, margin, business-rule error)
        # retried blindly wastes the retry budget and delays reacting to it — and if
        # it somehow *did* place, re-sending with the caller's client_order_id relies
        # on broker-side dedup rather than us needlessly resending a known-bad request.
        raise unless retryable?(e)
        raise if attempts >= RETRY_COUNT

        sleep RETRY_BASE_SLEEP * attempts
        retry
      end
    end

    def retryable?(error)
      RETRYABLE_ERROR_CLASSES.any? { |klass| error.is_a?(klass) }
    end
  end
end
