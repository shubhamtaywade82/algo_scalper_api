# frozen_string_literal: true

module OptionsBuying
  # Thread-safe Redis connection pool for OptionsBuying services.
  # Used by StateStore, StreamConsumer, BreakoutWatcher, and Solid Queue jobs.
  # Returns a wrapper that delegates all Redis commands to a checked-out connection
  # from the pool, enabling transparent thread-safe usage.
  class RedisPool
    class << self
      def instance
        @instance ||= build_pool
      end

      def shutdown
        @instance&.shutdown(&:quit)
        @instance = nil
      end

      private

      def build_pool
        size = (ENV['OPTIONS_BUYING_REDIS_POOL_SIZE'] || 10).to_i
        timeout = (ENV['OPTIONS_BUYING_REDIS_POOL_TIMEOUT'] || 5).to_i

        pool = ConnectionPool.new(size: size, timeout: timeout) do
          Redis.new(
            url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')
          )
        end

        # Wrap the pool with a delegator for transparent method forwarding
        PoolDelegator.new(pool)
      end
    end
  end

  # Delegates all method calls to a checked-out connection from the pool
  class PoolDelegator
    def initialize(pool)
      @pool = pool
    end

    def method_missing(method_name, ...)
      @pool.with do |conn|
        conn.public_send(method_name, ...)
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      @pool.with { |conn| conn.respond_to?(method_name, include_private) } || super
    end
  end
end