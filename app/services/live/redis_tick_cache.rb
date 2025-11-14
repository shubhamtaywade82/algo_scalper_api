# frozen_string_literal: true

require 'singleton'

module Live
  class RedisTickCache
    include Singleton

    PREFIX = 'tick'

    def store_tick(segment:, security_id:, data:)
      key = "#{PREFIX}:#{segment}:#{security_id}"

      existing = fetch_tick(segment, security_id)

      merged = existing.merge(data) do |field, old, new|
        if field == :ltp
          new.to_f.positive? ? new.to_f : old.to_f
        else
          new.nil? ? old : new
        end
      end

      redis.hmset(key, *merged.to_a.flatten)
      merged
    end

    def fetch_tick(segment, security_id)
      key = "#{PREFIX}:#{segment}:#{security_id}"
      raw = redis.hgetall(key)
      return {} if raw.empty?

      symbolize_and_cast(raw)
    end

    # -----------------------------
    # FETCH ALL TICKS IN REDIS
    # -----------------------------
    def fetch_all
      out = {}

      redis.scan_each(match: "#{PREFIX}:*") do |key|
        raw = redis.hgetall(key)
        next if raw.empty?

        seg = key.split(':')[1]
        sid = key.split(':')[2]
        out["#{seg}:#{sid}"] = symbolize_and_cast(raw)
      end

      out
    end

    # -----------------------------
    # CLEAR ALL REDIS TICKS
    # -----------------------------
    def clear
      redis.scan_each(match: "#{PREFIX}:*") { |key| redis.del(key) }
      true
    end

    def clear_tick(segment, security_id)
      key = "tick:#{segment}:#{security_id}"
      redis.del(key)
    end

    def self.delete(segment, security_id)
      key = "#{segment}:#{security_id}"
      @cache.delete(key)
    end

    def prune_stale(max_age: 30)
      cutoff = Time.current.to_i - max_age
      keys   = @redis.keys('tick:*')

      protected = protected_keys_set

      keys.each do |key|
        _, seg, sid = key.split(':')
        composite   = "#{seg}:#{sid}"

        # --- NEVER prune index ticks ---
        if seg == 'IDX_I'
          Rails.logger.debug { "[RedisTickCache] SKIP prune #{key} (reason: index feed)" }
          next
        end

        # --- NEVER prune protected/watchlist/active-position ticks ---
        if protected.include?(composite)
          Rails.logger.debug { "[RedisTickCache] SKIP prune #{key} (reason: protected key)" }
          next
        end

        data = @redis.hgetall(key)

        # --- Missing TS OR corrupted TS ---
        if data.blank? || !data['timestamp']
          Rails.logger.warn("[RedisTickCache] Pruning #{key} (reason: missing timestamp)")
          @redis.del(key)
          next
        end

        ts = data['timestamp'].to_i

        # --- Timestamp stale ---
        if ts < cutoff
          age = Time.current.to_i - ts
          Rails.logger.warn(
            "[RedisTickCache] Pruning #{key} (reason: stale tick; age=#{age}s > #{max_age}s)"
          )
          @redis.del(key)
          next
        end

        # --- KEEPING the tick ---
        Rails.logger.debug { "[RedisTickCache] KEEP #{key} (reason: fresh tick)" }
      end

      true
    rescue StandardError => e
      Rails.logger.error("[RedisTickCache] prune_stale ERROR: #{e.class} - #{e.message}")
      false
    end

    def protected_keys_set
      set = Set.new

      # 1. Index feeds
      %w[IDX_I IDX_BELLS IDX_FO].each do |seg|
        # If segment exists in your system
        @redis.keys("tick:#{seg}:*").each do |key|
          _, seg, sid = key.split(':')
          set << "#{seg}:#{sid}"
        end
      end

      # 2. Watchlist items
      watchlist = Array(AlgoConfig.fetch[:watchlist])
      watchlist.each do |item|
        seg = item[:segment]
        sid = item[:security_id]
        set << "#{seg}:#{sid}"
      end

      # 3. Active positions
      Live::PositionIndex.instance.all_keys.each do |k|
        set << k # keys are already in "SEG:SID" format
      end

      set
    end

    private

    def symbolize_and_cast(raw)
      raw.transform_keys!(&:to_sym)
         .transform_values! { |v| numeric?(v) ? v.to_f : v }
    end

    def numeric?(v)
      v.to_s =~ /\A-?\d+(\.\d+)?\z/
    end

    def redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    end
  end
end
