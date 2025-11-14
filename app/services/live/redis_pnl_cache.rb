# frozen_string_literal: true

require 'singleton'

module Live
  class RedisPnlCache
    include Singleton

    REDIS_KEY_PREFIX = 'pnl:tracker'
    TTL_SECONDS = 6.hours.to_i

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] init error: #{e.message}") if defined?(Rails)
      @redis = nil
    end

    # store only computed PnL (strings stored to Redis)
    def store_pnl(tracker_id:, pnl:, ltp:, hwm:, pnl_pct: nil, timestamp: Time.current)
      return false unless @redis

      key = pnl_key(tracker_id)
      data = {
        'pnl' => pnl.to_f.to_s,
        'pnl_pct' => pnl_pct&.to_f.to_s,
        'ltp' => ltp.to_f.to_s,
        'hwm_pnl' => hwm.to_f.to_s,
        'timestamp' => timestamp.to_i.to_s,
        'updated_at' => Time.current.to_i.to_s
      }

      @redis.hset(key, **data)
      # ensure TTL
      ttl = @redis.ttl(key).to_i
      @redis.expire(key, TTL_SECONDS) if ttl < (TTL_SECONDS / 2)
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] store_pnl error: #{e.message}") if defined?(Rails)
      false
    end

    def fetch_pnl(tracker_id)
      return nil unless @redis

      key = pnl_key(tracker_id)
      raw = @redis.hgetall(key)
      return nil if raw.nil? || raw.empty?

      {
        pnl: raw['pnl']&.to_f,
        pnl_pct: raw['pnl_pct']&.to_f,
        ltp: raw['ltp']&.to_f,
        hwm_pnl: raw['hwm_pnl']&.to_f,
        timestamp: raw['timestamp']&.to_i,
        updated_at: raw['updated_at']&.to_i
      }
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] fetch_pnl error: #{e.message}") if defined?(Rails)
      nil
    end

    # clear all pnl:* keys (dangerous but useful for tests/dev)
    def clear
      return false unless @redis

      pattern = "#{REDIS_KEY_PREFIX}:*"
      @redis.scan_each(match: pattern) { |k| @redis.del(k) }
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] clear error: #{e.message}") if defined?(Rails)
      false
    end

    def clear_tracker(tracker_id)
      return false unless @redis

      @redis.del(pnl_key(tracker_id))
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] clear_tracker error: #{e.message}") if defined?(Rails)
      false
    end

    # fetch everything: returns hash tracker_id => data
    def fetch_all
      return {} unless @redis

      out = {}
      pattern = "#{REDIS_KEY_PREFIX}:*"
      @redis.scan_each(match: pattern) do |key|
        id = key.split(':').last
        out[id.to_i] = fetch_pnl(id)
      end
      out
    rescue StandardError => e
      Rails.logger.error("[RedisPnL] fetch_all error: #{e.message}") if defined?(Rails)
      {}
    end

    def health_check
      return { status: :error, message: 'redis not init' } unless @redis

      @redis.ping
      { status: :ok, message: 'ok' }
    rescue StandardError => e
      { status: :error, message: e.message }
    end

    def each_tracker_key(&)
      pattern = "#{REDIS_KEY_PREFIX}:*"
      @redis.scan_each(match: pattern) do |key|
        tracker_id = key.split(':').last
        yield(key, tracker_id.to_s)
      end
    end

    private

    def pnl_key(id)
      "#{REDIS_KEY_PREFIX}:#{id}"
    end
  end
end
