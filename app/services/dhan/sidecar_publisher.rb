# frozen_string_literal: true

module Dhan
  class SidecarPublisher
    INTENT_CHANNEL = 'dhan:execution:intents'

    class << self
      def publish_intent(strategy:, params:, correlation_id:, risk_limits: {})
        payload = {
          intent_id: SecureRandom.uuid,
          strategy: strategy,
          params: params,
          correlation_id: correlation_id,
          risk_limits: risk_limits,
          created_at: Time.current.iso8601(3)
        }.to_json

        redis.publish(INTENT_CHANNEL, payload)
      rescue StandardError => e
        Rails.logger.error("[SidecarPublisher] Failed to publish intent: #{e.class} - #{e.message}")
        false
      end

      private

      def redis
        @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
      end
    end
  end
end
