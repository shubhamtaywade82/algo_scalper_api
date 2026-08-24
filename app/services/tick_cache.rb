# frozen_string_literal: true

require 'concurrent/map'
require 'singleton'

class TickCache
  include Singleton

  MEMORY_TTL = 1.5 # seconds

  def initialize
    @map = Concurrent::Map.new
  end

  # ------------------------
  # MASTER TICK HANDLER
  # ------------------------
  def put(raw_tick)
    tick = normalize(raw_tick)
    return if tick.nil?

    seg = tick[:segment]
    sid = tick[:security_id]
    key = cache_key(seg, sid)

    merged = @map.compute(key) do |_, existing|
      existing ||= {}
      previous_ltp = existing[:ltp]

      new_hash = existing.dup

      tick.each do |k, v|
        next if v.nil?

        case k
        when :segment, :security_id
          new_hash[k] = v

        when :ltp
          # LTP only updates if > 0
          new_hash[:ltp] = v.to_f if v.to_f.positive?

        else
          new_hash[k] = v
        end
      end

      # Restore previous LTP if missing
      new_hash[:ltp] = previous_ltp if new_hash[:ltp].nil? && previous_ltp
      new_hash[:cached_at] = Time.current

      new_hash
    end

    # Also update Redis TickCache for HA + PnL consumers
    Live::RedisTickCache.instance.store_tick(
      segment: seg,
      security_id: sid,
      data: merged
    )

    merged
  end

  # ------------------------
  # FETCH WITH REDIS FALLBACK
  # ------------------------
  def fetch(segment, security_id)
    key = cache_key(segment, security_id)

    mem = @map[key]
    return mem if mem && mem[:cached_at] && (Time.current - mem[:cached_at]) < MEMORY_TTL

    # Then fallback to Redis
    redis_tick = Live::RedisTickCache.instance.fetch_tick(segment, security_id)

    return nil if redis_tick.empty?

    # Preserve the real last-update time carried in Redis (stored as a Time#to_s string on
    # every genuine tick write) instead of stamping "now" — stamping now would make a residual
    # tick from hours ago (Redis TTL is 24h) look freshly arrived to callers that check
    # staleness, such as EntryGuard's entry-LTP resolution.
    redis_tick[:cached_at] = parse_cached_at(redis_tick[:cached_at]) || Time.current
    @map[key] = redis_tick

    redis_tick
  end

  # alias for compatibility
  def get(segment, security_id)
    fetch(segment, security_id)
  end

  # ------------------------
  # LTP WITH REDIS FALLBACK
  # ------------------------
  def ltp(segment, security_id)
    tick = fetch(segment, security_id)
    val = tick && tick[:ltp]
    val&.to_f
  end

  # ------------------------
  # Delete in-memory entry (used when unsubscribing / cleanup)
  # ------------------------
  def delete(segment, security_id)
    key = cache_key(segment, security_id)

    # Delete in-memory cache
    @map.delete(key)

    # Delete Redis tick key
    Live::RedisTickCache.instance.clear_tick(segment, security_id)

    true
  end

  def all
    mem = {}
    @map.each_pair { |k, v| mem[k] = v }

    redis = Live::RedisTickCache.instance.fetch_all

    # merge redis into memory snapshot (memory overrides for live session)
    redis.merge(mem)
  end

  delegate :clear, to: :@map

  private

  # ------------------------
  # Normalization
  # ------------------------
  def normalize(h)
    return nil unless h.is_a?(Hash)

    out = {}

    h.each do |k, v|
      sym = k.to_sym

      out[sym] =
        case sym
        when :ltp, :prev_close, :oi, :oi_prev
          v.to_f
        else
          v
        end
    end

    return nil if out[:segment].nil? || out[:security_id].nil?

    out[:segment] = out[:segment].to_s
    out[:security_id] = out[:security_id].to_s

    out
  end

  def cache_key(seg, sid)
    "#{seg}:#{sid}"
  end

  def parse_cached_at(value)
    return value if value.is_a?(Time)

    Time.zone.parse(value.to_s)
  rescue StandardError
    nil
  end
end
