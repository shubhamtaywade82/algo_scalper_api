# frozen_string_literal: true

require 'singleton'

module Signal
  # Full diagnostic signal metadata — kept in Redis during the live evaluation cycle.
  # PostgreSQL stores a slim metadata row; merge via TradingSignal#effective_metadata.
  class LiveMetadataCache
    include Singleton

    REDIS_KEY_PREFIX = 'signal:live_metadata'
    TTL_SECONDS = 24.hours.to_i

    SLIM_DB_KEYS = %w[
      regime strategy strategy_mode smc_decision smc_permission validation_passed
      entry_path entry_outcome entry_blocked_reason entry_skip_stage entry_skip_code
      adx_value confidence_score regime_confidence gamma_pressure iv_rank_proxy
      theta_risk_score effective_timeframe
    ].freeze

    class << self
      def slim_metadata(full_metadata)
        full_metadata.stringify_keys.slice(*SLIM_DB_KEYS).compact
      end
    end

    def initialize
      @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    rescue StandardError => e
      Rails.logger.error("[Signal::LiveMetadataCache] init error: #{e.message}") if defined?(Rails)
      @redis = nil
    end

    def store(signal_id, metadata)
      return false unless signal_id && @redis && metadata.is_a?(Hash)

      @redis.set(metadata_key(signal_id), metadata.to_json, ex: TTL_SECONDS)
      true
    rescue StandardError => e
      Rails.logger.error("[Signal::LiveMetadataCache] store error signal=#{signal_id}: #{e.message}")
      false
    end

    def fetch(signal_id)
      return {} unless signal_id && @redis

      raw = @redis.get(metadata_key(signal_id))
      return {} if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    rescue StandardError => e
      Rails.logger.error("[Signal::LiveMetadataCache] fetch error signal=#{signal_id}: #{e.message}")
      {}
    end

    def merge(signal_id, fragment)
      return false unless signal_id && fragment.is_a?(Hash) && fragment.any?

      current = fetch(signal_id)
      store(signal_id, current.merge(fragment.stringify_keys))
    end

    def clear(signal_id)
      return false unless signal_id && @redis

      @redis.del(metadata_key(signal_id))
      true
    rescue StandardError => e
      Rails.logger.error("[Signal::LiveMetadataCache] clear error signal=#{signal_id}: #{e.message}")
      false
    end

    private

    def metadata_key(signal_id)
      "#{REDIS_KEY_PREFIX}:#{signal_id}"
    end
  end
end
