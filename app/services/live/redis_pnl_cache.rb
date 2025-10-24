# frozen_string_literal: true

require "singleton"

module Live
  class RedisPnlCache
    include Singleton

    REDIS_KEY_PREFIX = "pnl:tracker"
    TTL_SECONDS = 1.hour.to_i

    def initialize
      @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    rescue StandardError => e
      Rails.logger.error("Failed to initialize Redis PnL cache: #{e.message}")
      @redis = nil
    end

    def store_pnl(tracker_id:, pnl:, pnl_pct: nil, ltp: nil, timestamp: Time.current)
      return unless @redis

      key = pnl_key(tracker_id)
      data = {
        pnl: pnl.to_f,
        pnl_pct: pnl_pct&.to_f,
        ltp: ltp&.to_f,
        timestamp: timestamp.to_i,
        updated_at: Time.current.to_i
      }

      @redis.hset(key, data)
      @redis.expire(key, TTL_SECONDS)

      Rails.logger.debug("[RedisPnL] Stored PnL for tracker #{tracker_id}: #{pnl}")
    rescue StandardError => e
      Rails.logger.error("Failed to store PnL in Redis for tracker #{tracker_id}: #{e.message}")
    end

    def fetch_pnl(tracker_id)
      return nil unless @redis

      key = pnl_key(tracker_id)
      data = @redis.hgetall(key)
      return nil if data.empty?

      {
        pnl: data["pnl"]&.to_f,
        pnl_pct: data["pnl_pct"]&.to_f,
        ltp: data["ltp"]&.to_f,
        timestamp: data["timestamp"]&.to_i,
        updated_at: data["updated_at"]&.to_i
      }
    rescue StandardError => e
      Rails.logger.error("Failed to fetch PnL from Redis for tracker #{tracker_id}: #{e.message}")
      nil
    end

    def store_tick(tracker_id:, ltp:, timestamp: Time.current)
      return unless @redis

      key = tick_key(tracker_id)
      data = {
        ltp: ltp.to_f,
        timestamp: timestamp.to_i,
        updated_at: Time.current.to_i
      }

      @redis.hset(key, data)
      @redis.expire(key, TTL_SECONDS)

      Rails.logger.debug("[RedisPnL] Stored tick for tracker #{tracker_id}: #{ltp}")
    rescue StandardError => e
      Rails.logger.error("Failed to store tick in Redis for tracker #{tracker_id}: #{e.message}")
    end

    def fetch_tick(tracker_id)
      return nil unless @redis

      key = tick_key(tracker_id)
      data = @redis.hgetall(key)
      return nil if data.empty?

      {
        ltp: data["ltp"]&.to_f,
        timestamp: data["timestamp"]&.to_i,
        updated_at: data["updated_at"]&.to_i
      }
    rescue StandardError => e
      Rails.logger.error("Failed to fetch tick from Redis for tracker #{tracker_id}: #{e.message}")
      nil
    end

    def is_tick_fresh?(tracker_id, max_age_seconds: 5)
      tick_data = fetch_tick(tracker_id)
      return false unless tick_data

      age_seconds = Time.current.to_i - tick_data[:timestamp]
      age_seconds <= max_age_seconds
    rescue StandardError => e
      Rails.logger.error("Failed to check tick freshness for tracker #{tracker_id}: #{e.message}")
      false
    end

    def clear_tracker(tracker_id)
      return unless @redis

      pnl_key = pnl_key(tracker_id)
      tick_key = tick_key(tracker_id)

      @redis.del(pnl_key, tick_key)
      Rails.logger.info("[RedisPnL] Cleared cache for tracker #{tracker_id}")
    rescue StandardError => e
      Rails.logger.error("Failed to clear Redis cache for tracker #{tracker_id}: #{e.message}")
    end

    def health_check
      return { status: :error, message: "Redis not initialized" } unless @redis

      @redis.ping
      { status: :ok, message: "Redis PnL cache is healthy" }
    rescue StandardError => e
      { status: :error, message: "Redis PnL cache error: #{e.message}" }
    end

    private

    def pnl_key(tracker_id)
      "#{REDIS_KEY_PREFIX}:#{tracker_id}"
    end

    def tick_key(tracker_id)
      "#{REDIS_KEY_PREFIX}:tick:#{tracker_id}"
    end
  end
end
