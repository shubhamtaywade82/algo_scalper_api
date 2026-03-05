# frozen_string_literal: true

require 'singleton'

module Live
  # Redis-backed service to track heartbeats of background processes
  # (Market Feed, Scheduler) for cross-process status reporting.
  class SystemStatusCache
    include Singleton

    PREFIX = 'system_status'
    HEARTBEAT_TTL = 30.seconds

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[SystemStatusCache] init error: #{e.message}") if defined?(Rails)
      @redis = nil
    end

    def report_heartbeat(service_name)
      return false unless @redis

      key = heartbeat_key(service_name)
      @redis.setex(key, HEARTBEAT_TTL.to_i, Time.current.to_i.to_s)
      true
    rescue StandardError => e
      Rails.logger.error("[SystemStatusCache] report_heartbeat error: #{e.message}") if defined?(Rails)
      false
    end

    def running?(service_name)
      return false unless @redis

      @redis.exists?(heartbeat_key(service_name))
    rescue StandardError
      false
    end

    def all_statuses
      {
        ws_market_feed: running?(:ws_market_feed),
        scheduler: running?(:scheduler) ? 'running' : 'unknown'
      }
    end

    private

    def heartbeat_key(service_name)
      "#{PREFIX}:heartbeat:#{service_name}"
    end
  end
end
