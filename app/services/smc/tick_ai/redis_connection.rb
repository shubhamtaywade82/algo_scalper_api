# frozen_string_literal: true

module Smc
  module TickAi
    # Shared Redis client for tick-AI throttle and rising-edge snapshots.
    module RedisConnection
      module_function

      def client
        @client ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      end
    end
  end
end
