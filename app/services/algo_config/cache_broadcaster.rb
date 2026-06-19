# frozen_string_literal: true

class AlgoConfig
  # Cross-process cache bust when algo_config_document changes (web ↔ trading daemon).
  class CacheBroadcaster
    CHANNEL = 'algo_config:invalidate'

    class << self
      def publish!(source:)
        return unless enabled?

        payload = { source: source, at: Time.current.iso8601(3) }.to_json
        redis.publish(CHANNEL, payload)
      rescue StandardError => e
        Rails.logger.warn("[AlgoConfig::CacheBroadcaster] publish failed: #{e.class} - #{e.message}")
      end

      def start_subscriber!
        return unless enabled?
        return if @subscriber_thread&.alive?

        @subscriber_thread = Thread.new do
          Thread.current.name = 'algo-config-cache-subscriber'
          subscribe_loop
        end
      end

      private

      def enabled?
        return false if Rails.env.test?

        ENV.fetch('ALGO_CONFIG_REDIS_BROADCAST', 'true') != 'false'
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      end

      def subscribe_loop
        redis.subscribe(CHANNEL) do |on|
          on.message do |_channel, _message|
            AlgoConfig.reset!
            Signal::FastEntryMode.reset!
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[AlgoConfig::CacheBroadcaster] subscriber error: #{e.class} - #{e.message}")
        sleep 1
        retry
      end
    end
  end
end
