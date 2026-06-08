# frozen_string_literal: true

require 'singleton'

module Options
  # IvRankTracker — rolling-window IV history & percentile rank, Redis-backed
  #
  # PROBLEM: Entry validation (Signal::Engine#validate_iv_rank_real) gates on a flat
  # absolute IV band (iv_rank_max: 0.75 / iv_rank_min: 0.10). But "high IV" is relative —
  # 25% IV is elevated for a calm index in a quiet month and cheap during an event week.
  # A fixed absolute ceiling either blocks good entries in naturally-higher-vol regimes
  # or lets through entries that are actually expensive relative to their own recent range.
  #
  # This service samples each index's ATM IV (fed by Signal::Engine#fetch_real_atm_iv)
  # into a Redis sorted-set rolling window and computes the CURRENT sample's percentile
  # rank against that recent history — "today's IV is cheaper than 80% of the last N
  # samples" — which is the textbook IV-RANK definition options sellers/buyers actually use.
  #
  # Storage: one Redis sorted set per index (`iv_history:<INDEX_KEY>`), scored by
  # timestamp, capped at max_samples and expired after window_days — mirrors the
  # Singleton + raw-Redis rolling-store pattern used by Live::RedisPnlCache.
  #
  # Config (config/algo.yml under options.iv_rank_tracker):
  #   iv_rank_tracker:
  #     window_days: 20
  #     max_samples: 500
  #     min_samples: 30   # below this, percentile_rank returns nil (not enough history yet)
  class IvRankTracker
    include Singleton

    REDIS_KEY_PREFIX = 'iv_history'
    DEFAULT_WINDOW_DAYS = 20
    DEFAULT_MAX_SAMPLES = 500
    DEFAULT_MIN_SAMPLES = 30

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[IvRankTracker] init error: #{e.message}") if defined?(Rails)
      @redis = nil
    end

    # Records one ATM-IV sample (decimal form, e.g. 0.145) for the given index.
    def record_sample(index_key:, iv:)
      return unless @redis
      return unless index_key.present? && iv.to_f.positive?

      key = history_key(index_key)
      now = Time.current.to_f
      @redis.zadd(key, now, "#{now}:#{iv.to_f}")
      trim(key)
      @redis.expire(key, window_seconds)
      true
    rescue StandardError => e
      Rails.logger.warn("[IvRankTracker] record_sample error: #{e.class} - #{e.message}")
      false
    end

    # Percentile rank (0.0–1.0) of `iv` against the recorded historical window —
    # the fraction of recorded samples strictly below it. Returns nil when history
    # is too thin to be meaningful (caller should fall back to the absolute band).
    def percentile_rank(index_key:, iv:)
      return nil unless @redis

      samples = history(index_key)
      return nil if samples.size < min_samples

      below = samples.count { |s| s < iv.to_f }
      below.to_f / samples.size
    rescue StandardError => e
      Rails.logger.warn("[IvRankTracker] percentile_rank error: #{e.class} - #{e.message}")
      nil
    end

    def sample_count(index_key)
      return 0 unless @redis

      history(index_key).size
    rescue StandardError
      0
    end

    private

    def history(index_key)
      raw = @redis.zrange(history_key(index_key), 0, -1)
      raw.map { |entry| entry.split(':', 2).last.to_f }
    end

    def trim(key)
      size = @redis.zcard(key)
      @redis.zremrangebyrank(key, 0, size - max_samples - 1) if size > max_samples
    end

    def history_key(index_key)
      "#{REDIS_KEY_PREFIX}:#{index_key}"
    end

    def window_seconds
      window_days * 24 * 60 * 60
    end

    def window_days
      cfg.fetch(:window_days, DEFAULT_WINDOW_DAYS).to_i
    end

    def max_samples
      cfg.fetch(:max_samples, DEFAULT_MAX_SAMPLES).to_i
    end

    def min_samples
      cfg.fetch(:min_samples, DEFAULT_MIN_SAMPLES).to_i
    end

    def cfg
      AlgoConfig.fetch.dig(:options, :iv_rank_tracker) || {}
    rescue StandardError
      {}
    end
  end
end
