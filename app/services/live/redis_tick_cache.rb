# frozen_string_literal: true

require "singleton"

module Live
  class RedisTickCache
    include Singleton

    PREFIX = "tick".freeze

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

        seg, sid = key.split(":")[1], key.split(":")[2]
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

    private

    def symbolize_and_cast(raw)
      raw.transform_keys!(&:to_sym)
         .transform_values! { |v| numeric?(v) ? v.to_f : v }
    end

    def numeric?(v)
      v.to_s =~ /\A-?\d+(\.\d+)?\z/
    end

    def redis
      @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"))
    end
  end
end
