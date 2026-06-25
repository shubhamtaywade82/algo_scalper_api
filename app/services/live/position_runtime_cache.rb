# frozen_string_literal: true

require 'singleton'

module Live
  # Ephemeral per-position runtime fields (peak premium, trailing highs, etc.).
  # Live path reads/writes Redis; DB meta is flushed on exit via {#flush_to_meta!}.
  class PositionRuntimeCache
    include Singleton

    REDIS_KEY_PREFIX = 'position:runtime'
    TTL_SECONDS = 6.hours.to_i

    RUNTIME_FIELDS = %w[
      peak_premium peak_premium_at highest_price lowest_price peak_trend_score
      telegram_notified_milestones hwm_pnl_pct
    ].freeze

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[PositionRuntimeCache] init error: #{e.message}") if defined?(Rails)
      @redis = nil
    end

    def fetch(tracker_id)
      return {} unless tracker_id && @redis

      raw = @redis.hgetall(runtime_key(tracker_id))
      raw.each_with_object({}) do |(key, value), memo|
        memo[key.to_sym] = deserialize_field(key, value)
      end
    rescue StandardError => e
      Rails.logger.error("[PositionRuntimeCache] fetch error tracker=#{tracker_id}: #{e.message}")
      {}
    end

    def merge(tracker_id, fields)
      return false unless tracker_id && @redis && fields.is_a?(Hash) && fields.any?

      payload = fields.stringify_keys.slice(*RUNTIME_FIELDS)
      return false if payload.empty?

      key = runtime_key(tracker_id)
      @redis.hset(key, **serialize_fields(payload))
      @redis.expire(key, TTL_SECONDS)
      true
    rescue StandardError => e
      Rails.logger.error("[PositionRuntimeCache] merge error tracker=#{tracker_id}: #{e.message}")
      false
    end

    def peak_premium_for(tracker)
      record = tracker.is_a?(PositionTracker) ? tracker : PositionTracker.find_by(id: tracker)
      return 0.0 unless record

      runtime = fetch(record.id)
      return runtime[:peak_premium].to_f if runtime.key?(:peak_premium)

      record.meta&.dig('peak_premium').to_f
    end

    def peak_premium_at_for(tracker)
      record = tracker.is_a?(PositionTracker) ? tracker : PositionTracker.find_by(id: tracker)
      return Time.current unless record

      cached = fetch(record.id)[:peak_premium_at]
      return Time.zone.parse(cached.to_s) if cached.present?

      raw = record.meta&.dig('peak_premium_at')
      raw ? Time.zone.parse(raw.to_s) : record.created_at
    end

    def update_peak_premium!(tracker, ltp)
      current = peak_premium_for(tracker)
      price = ltp.to_f
      return false unless price.positive? && price > current

      merge(tracker.id, peak_premium: price, peak_premium_at: Time.current.iso8601)
    end

    def highest_price_for(tracker)
      cached = fetch(tracker.id)[:highest_price]
      return cached.to_f if cached.present?

      tracker.highest_price.to_f.nonzero? || tracker.highest_price.to_f
    end

    def update_highest_price!(tracker, price)
      current = highest_price_for(tracker)
      high = price.to_f
      return false unless high.positive? && high > current

      merge(tracker.id, highest_price: high)
    end

    def telegram_milestones_for(tracker)
      cached = fetch(tracker.id)[:telegram_notified_milestones]
      return Array(cached) if cached.present?

      Array(tracker.meta&.dig('telegram_notified_milestones'))
    end

    def append_telegram_milestone!(tracker, milestone_key)
      milestones = telegram_milestones_for(tracker)
      return false if milestones.include?(milestone_key)

      merge(tracker.id, telegram_notified_milestones: (milestones + [milestone_key]).uniq)
    end

    def flush_to_meta!(meta_hash, tracker_id)
      runtime = fetch(tracker_id)
      return meta_hash if runtime.empty?

      merged = meta_hash.is_a?(Hash) ? meta_hash.deep_stringify_keys.dup : {}
      runtime.each do |key, value|
        next if value.nil?

        merged[key.to_s] = value
      end
      merged
    end

    def clear(tracker_id)
      return false unless tracker_id && @redis

      @redis.del(runtime_key(tracker_id))
      true
    rescue StandardError => e
      Rails.logger.error("[PositionRuntimeCache] clear error tracker=#{tracker_id}: #{e.message}")
      false
    end

    private

    def runtime_key(tracker_id)
      "#{REDIS_KEY_PREFIX}:#{tracker_id}"
    end

    def serialize_fields(payload)
      payload.transform_values do |value|
        case value
        when Array then value.to_json
        else value.to_s
        end
      end
    end

    def deserialize_field(key, value)
      return JSON.parse(value) if key == 'telegram_notified_milestones'
      return value.to_f if %w[peak_premium highest_price lowest_price hwm_pnl_pct peak_trend_score].include?(key)

      value
    rescue JSON::ParserError
      value
    end
  end
end
