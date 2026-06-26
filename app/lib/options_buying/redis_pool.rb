# frozen_string_literal: true

module OptionsBuying
  # Thread-safe Redis connection pool for OptionsBuying services.
  # Used by StateStore, StreamConsumer, BreakoutWatcher, and Solid Queue jobs.
  # Returns a ConnectionPool::Wrapper that delegates all Redis commands to
  # a checked-out connection from the pool, enabling transparent thread-safe usage.
  class RedisPool
    class << self
      def instance
        @instance ||= build_wrapper
      end

      def shutdown
        @instance&.__getobj__&.shutdown { |conn| conn.quit }
        @instance = nil
      end

      private

      def build_wrapper
        pool = build_pool
        ConnectionPool::Wrapper.new(pool)
      end

      def build_pool
        size = (ENV['OPTIONS_BUYING_REDIS_POOL_SIZE'] || 10).to_i
        timeout = (ENV['OPTIONS_BUYING_REDIS_POOL_TIMEOUT'] || 5).to_i

        ConnectionPool.new(size: size, timeout: timeout) do
          Redis.new(
            url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'),
            thread_safe: true
          )
        end
      end
    end
  end
end