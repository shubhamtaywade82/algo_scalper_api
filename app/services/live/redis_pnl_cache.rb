# frozen_string_literal: true

require 'singleton'

module Live
  class RedisPnlCache
    include Singleton

    REDIS_KEY_PREFIX = 'pnl:tracker'
    TTL_SECONDS = 1.hour.to_i

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    rescue StandardError
      # Rails.logger.error('Failed to initialize Redis PnL cache')
      @redis = nil
    end

    def store_pnl(tracker_id:, pnl:, pnl_pct: nil, ltp: nil, hwm: nil, timestamp: Time.current)
      return unless @redis

      key = pnl_key(tracker_id)

      # Convert all values to strings for Redis (Redis stores everything as strings)
      data = {}
      data['pnl'] = pnl.to_f.to_s if pnl
      data['pnl_pct'] = pnl_pct.to_f.to_s if pnl_pct
      data['hwm_pnl'] = hwm.to_f.to_s if hwm
      data['ltp'] = ltp.to_f.to_s if ltp
      data['timestamp'] = timestamp.to_i.to_s
      data['updated_at'] = Time.current.to_i.to_s

      return if data.empty?

      @redis.hset(key, data)
      @redis.expire(key, TTL_SECONDS)

      # Rails.logger.debug { "[RedisPnL] Stored PnL for tracker #{tracker_id}: pnl=#{pnl}, hwm=#{hwm}, ltp=#{ltp}" }
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] Failed to store PnL in Redis for tracker #{tracker_id}: #{e.message}") if defined?(Rails.logger)
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
      # Rails.logger.error("Failed to fetch PnL from Redis for tracker #{tracker_id}")
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

    def clear_tracker(tracker_id)
      return unless @redis

      pnl_key = pnl_key(tracker_id)
      @redis.del(pnl_key)
      # Rails.logger.info("[RedisPnL] Cleared PnL cache for tracker #{tracker_id}")
    rescue StandardError
      # Rails.logger.error("Failed to clear Redis PnL cache for tracker #{tracker_id}")
    end

    def each_tracker_key
      return enum_for(:each_tracker_key) unless block_given?
      return unless @redis

      @redis.scan_each(match: "#{REDIS_KEY_PREFIX}:*") do |key|
        tracker_id = key.split(':').last
        yield(key, tracker_id)
      end
    rescue StandardError
      # Rails.logger.error('[RedisPnL] Failed to iterate tracker keys')
    end

    def clear_tick(segment:, security_id:)
      return unless @redis

      key = tick_key(segment, security_id)
      @redis.del(key)
      # Rails.logger.info("[RedisPnL] Cleared tick cache for #{segment}:#{security_id}")
    rescue StandardError
      # Rails.logger.error("Failed to clear Redis tick cache for #{segment}:#{security_id}")
    end

    def health_check
      return { status: :error, message: 'Redis not initialized' } unless @redis

      @redis.ping
      { status: :ok, message: 'Redis PnL cache is healthy' }
    rescue StandardError
      { status: :error, message: 'Redis PnL cache error' }
    end

    private

    def pnl_key(tracker_id)
      "#{REDIS_KEY_PREFIX}:#{tracker_id}"
    end

    def tick_key(segment, security_id)
      "tick:#{segment}:#{security_id}"
    end
  end
end
