# frozen_string_literal: true

module DataQuality
  # Samples Live::FeedHealthService's existing tick-staleness check once a minute during
  # market hours and accumulates a daily stale/total ratio in Rails.cache. Zero new
  # hot-path instrumentation — this only reads a cache value FeedHealthService already
  # maintains. Data_quality::DailyCheckJob reads these counters at end of day and clears them.
  #
  # Plain read-then-write instead of Rails.cache.increment: the test env's NullStore
  # doesn't implement #increment (same constraint hit in Orders::Placer#record_order_failure!).
  class TickStalenessSamplerJob < ApplicationJob
    queue_as :background

    def self.cache_keys_for(date)
      { total: "dq:tick_staleness:#{date}:total", stale: "dq:tick_staleness:#{date}:stale" }
    end

    def perform
      keys = self.class.cache_keys_for(Date.current)

      bump!(keys[:total])
      bump!(keys[:stale]) if Live::FeedHealthService.instance.stale?(:ticks)
    end

    private

    def bump!(key)
      count = (Rails.cache.read(key) || 0) + 1
      Rails.cache.write(key, count, expires_in: 25.hours)
    end
  end
end
