# frozen_string_literal: true

require 'singleton'

module Live
  class RedisPnlCache
    include Singleton

    REDIS_KEY_PREFIX = 'pnl:tracker'
    TTL_SECONDS = 6.hours.to_i

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    rescue StandardError
      @redis = nil
    end

    # ------------------------------------------------------------
    # ONLY STORE PNL — NEVER STORE TICK HERE
    # ------------------------------------------------------------
    def store_pnl(tracker_id:, pnl:, pnl_pct:, ltp:, hwm:, timestamp: Time.current)
      return unless @redis

      key = pnl_key(tracker_id)

      data = {
        'pnl' => pnl.to_f.to_s,
        'pnl_pct' => pnl_pct.to_f.to_s,
        'ltp' => ltp.to_f.to_s,
        'hwm_pnl' => hwm.to_f.to_s,
        'timestamp' => timestamp.to_i.to_s,
        'updated_at' => Time.current.to_i.to_s
      }

      @redis.hset(key, **data)

      ttl = @redis.ttl(key).to_i
      @redis.expire(key, TTL_SECONDS) if ttl < TTL_SECONDS / 2
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] Failed to store PnL #{tracker_id}: #{e.message}")
    end

    def store_tick(segment:, security_id:, ltp:, timestamp: Time.current)
      return unless @redis
      return unless ltp && ltp.to_f.positive?

      key = tick_key(segment, security_id)

      # Convert all values to strings for Redis
      data = {
        'ltp' => ltp.to_f.to_s,
        'timestamp' => timestamp.to_i.to_s,
        'updated_at' => Time.current.to_i.to_s
      }

      @redis.hset(key, data)
      @redis.expire(key, TTL_SECONDS)

      # Rails.logger.debug { "[RedisPnL] Stored tick for #{segment}:#{security_id}: #{ltp}" }
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] Failed to store tick in Redis for #{segment}:#{security_id}: #{e.message}") if defined?(Rails.logger)
    end


    def fetch_pnl(tracker_id)
      return nil unless @redis

      key = pnl_key(tracker_id)

      data = @redis.hgetall(key)
      return nil if data.empty?

      {
        pnl: data['pnl']&.to_f,
        pnl_pct: data['pnl_pct']&.to_f,
        ltp: data['ltp']&.to_f,
        hwm_pnl: data['hwm_pnl']&.to_f,
        timestamp: data['timestamp']&.to_i,
        updated_at: data['updated_at']&.to_i
      }
    rescue StandardError
      nil
    end

    def store_tick(segment:, security_id:, ltp:, timestamp: Time.current)
      return unless @redis
      return unless ltp && ltp.to_f.positive?

      key = tick_key(segment, security_id)

      # Convert all values to strings for Redis
      data = {
        'ltp' => ltp.to_f.to_s,
        'timestamp' => timestamp.to_i.to_s,
        'updated_at' => Time.current.to_i.to_s
      }

      @redis.hset(key, data)
      @redis.expire(key, TTL_SECONDS)

      # Rails.logger.debug { "[RedisPnL] Stored tick for #{segment}:#{security_id}: #{ltp}" }
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] Failed to store tick in Redis for #{segment}:#{security_id}: #{e.message}") if defined?(Rails.logger)
    end

    def fetch_tick(segment:, security_id:)
      return nil unless @redis

      key = tick_key(segment, security_id)
      data = @redis.hgetall(key)
      return nil if data.empty?

      {
        ltp: data['ltp']&.to_f,
        timestamp: data['timestamp']&.to_i,
        updated_at: data['updated_at']&.to_i
      }
    rescue StandardError
      # Rails.logger.error("Failed to fetch tick from Redis for #{segment}:#{security_id}")
      nil
    end

    def is_tick_fresh?(segment:, security_id:, max_age_seconds: 5)
      tick_data = fetch_tick(segment: segment, security_id: security_id)
      return false unless tick_data

      age_seconds = Time.current.to_i - tick_data[:timestamp]
      age_seconds <= max_age_seconds
    rescue StandardError
      # Rails.logger.error("Failed to check tick freshness for #{segment}:#{security_id}")
      false
    end

    # ------------------------------------------------------------
    # REMOVE TICK HANDLING COMPLETELY
    # ------------------------------------------------------------

    def clear_tracker(tracker_id)
      return unless @redis

      @redis.del(pnl_key(tracker_id))
    end

    def clear
      pattern = "#{REDIS_KEY_PREFIX}:*"
      @redis.scan_each(match: pattern) do |key|
        @redis.del(key)
      end
      true
    end

    def each_tracker_key
      return enum_for(:each_tracker_key) unless block_given?
      return unless @redis

      @redis.scan_each(match: "#{REDIS_KEY_PREFIX}:*") do |key|
        tracker_id = key.split(':').last
        yield(key, tracker_id)
      end
    end

    def health_check
      return { status: :error, message: 'Redis not initialized' } unless @redis

      @redis.ping
      { status: :ok, message: 'Redis PnL cache is healthy' }
    rescue StandardError
      { status: :error, message: 'Redis PnL cache error' }
    end

    private

    def tick_key(segment, security_id)
      "tick:#{segment}:#{security_id}"
    end

    def pnl_key(id)
      "#{REDIS_KEY_PREFIX}:#{id}"
    end
  end
end
