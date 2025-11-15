# frozen_string_literal: true

require 'singleton'

module Live
  class RedisTickCache
    include Singleton

    PREFIX = 'tick'

    # Store a tick as a hash under tick:<SEG>:<SID>
    # data is a hash of symbol/string keys -> values
    def store_tick(segment:, security_id:, data:)
      key = redis_key(segment, security_id)

      existing = fetch_tick(segment, security_id) || {}

      # Normalize both hashes to string keys for consistent storage/merging
      existing_str = stringify_keys(existing)
      incoming_str = stringify_keys(data)

      merged = existing_str.merge(incoming_str) do |field, old, new|
        if field.to_s == 'ltp'
          # prefer a positive new LTP, otherwise keep old
          new_f = numeric_to_f(new)
          old_f = numeric_to_f(old)
          new_f.positive? ? new_f : old_f
        else
          new.nil? ? old : new
        end
      end

      # hmset expects a flat array: key1, val1, key2, val2...
      args = merged.flat_map { |k, v| [k.to_s, v.to_s] }
      redis.hmset(key, *args)

      # return symbolized/casted form for convenience
      symbolize_and_cast(merged)
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] store_tick ERROR: #{e.class} - #{e.message}")
      {}
    end

    # Fetch a single tick as a hash with symbol keys and numeric casting
    def fetch_tick(segment, security_id)
      key = redis_key(segment, security_id)
      raw = redis.hgetall(key)
      return {} if raw.blank?

      symbolize_and_cast(raw)
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] fetch_tick ERROR: #{e.class} - #{e.message}")
      {}
    end

    # Fetch all tick keys: returns { "SEG:SID" => {..tick..} }
    def fetch_all
      out = {}
      redis.scan_each(match: "#{PREFIX}:*") do |key|
        raw = redis.hgetall(key)
        next if raw.blank?

        parts = key.split(':', 3) # ["tick", "SEG", "SID"]
        seg = parts[1]
        sid = parts[2]
        out["#{seg}:#{sid}"] = symbolize_and_cast(raw)
      end
      out
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] fetch_all ERROR: #{e.class} - #{e.message}")
      {}
    end

    # Clear all ticks
    def clear
      redis.scan_each(match: "#{PREFIX}:*") { |key| redis.del(key) }
      true
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] clear ERROR: #{e.class} - #{e.message}")
      false
    end

    def clear_tick(segment, security_id)
      redis.del(redis_key(segment, security_id))
      true
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] clear_tick ERROR: #{e.class} - #{e.message}")
      false
    end

    # Delete wrapper used elsewhere as class method
    def self.delete(segment, security_id)
      key = "tick:#{segment}:#{security_id}"
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0')).del(key)
      true
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] self.delete ERROR: #{e.class} - #{e.message}")
      false
    end

    # Prune stale ticks older than max_age seconds.
    # Keeps index feeds and protected keys (watchlist/active positions).
    def prune_stale(max_age: 60)
      cutoff = Time.current.to_i - max_age
      protected = protected_keys_set

      redis.scan_each(match: "#{PREFIX}:*") do |key|
        _, seg, sid = key.split(':', 3)
        composite = "#{seg}:#{sid}"

        # never prune index feeds
        if seg == 'IDX_I'
          Rails.logger.debug { "[RedisTickCache] SKIP prune #{key} (index feed)" }
          next
        end

        # keep tracked positions
        if Live::PositionIndex.instance.tracked?(seg, sid)
          Rails.logger.debug { "[RedisTickCache] SKIP prune #{key} (position index tracked)" }
          next
        end

        # keep protected keys (watchlist/active)
        if protected.include?(composite)
          Rails.logger.debug { "[RedisTickCache] SKIP prune #{key} (protected)" }
          next
        end

        # check timestamp field if present
        data = redis.hgetall(key)
        ts_str = data['timestamp'] || data[:timestamp]
        if ts_str.nil? || ts_str.to_s.strip.empty?
          # no timestamp => treat as stale and remove
          Rails.logger.warn("[RedisTickCache] Pruning #{key} (missing timestamp)")
          redis.del(key)
          next
        end

        ts = ts_str.to_i
        age = Time.current.to_i - ts
        if ts < cutoff
          Rails.logger.warn("[RedisTickCache] Pruning #{key} (stale; age=#{age}s > #{max_age}s)")
          redis.del(key)
          next
        end

        Rails.logger.debug { "[RedisTickCache] KEEP #{key} (fresh; age=#{age}s)" }
      rescue StandardError => e
        Rails.logger.error("[RedisTickCache] prune_stale loop ERROR key=#{key} - #{e.class}: #{e.message}")
        next
      end

      true
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] prune_stale ERROR: #{e.class} - #{e.message}")
      false
    end

    # Build set of protected keys: index, watchlist, active positions
    def protected_keys_set
      set = Set.new

      # 1. Index feeds (existing tick keys per segment)
      redis.scan_each(match: 'tick:IDX_I:*') do |key|
        _, s, sid = key.split(':', 3)
        set << "#{s}:#{sid}" if s && sid
      end

      # 2. Watchlist items (AlgoConfig may be nil or not an array)
      begin
        watchlist = Array(AlgoConfig.fetch[:watchlist])
        watchlist.each do |item|
          seg = item && (item[:segment] || item['segment'])
          sid = item && (item[:security_id] || item['security_id'])
          set << "#{seg}:#{sid}" if seg && sid
        end
      rescue StandardError
        # ignore config errors
      end

      # 3. Active positions (PositionIndex returns "SEG:SID" strings)
      begin
        Live::PositionIndex.instance.all_keys.each do |k|
          set << k.to_s
        end
      rescue StandardError
        # if PositionIndex not available, ignore
      end

      set
    end

    private

    def symbolize_and_cast(raw)
      # raw is a hash with string keys and string values
      raw.each_with_object({}) do |(k, v), acc|
        key = k.to_s.strip
        val = v
        acc[key.to_sym] = numeric?(val) ? numeric_to_f(val) : val
      end
    end

    def numeric?(value)
      value.to_s =~ /\A-?\d+(\.\d+)?\z/
    end

    def numeric_to_f(value)
      Float(value)
    rescue StandardError
      0.0
    end

    def stringify_keys(hash)
      hash.transform_keys(&:to_s)
    end

    def redis_key(segment, security_id)
      "#{PREFIX}:#{segment}:#{security_id}"
    end

    def redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    end
  end
end
