# frozen_string_literal: true

module OptionsBuying
  class TelemetrySinkJob < ApplicationJob
    queue_as :background

    def perform(index_key:, event_type:, occurred_at:, security_id: nil, metadata: {})
      return unless Mode.telemetry_sink_enabled?

      OptionsBuyingSignalEvent.create!(
        index_key: index_key.to_s.upcase,
        security_id: security_id&.to_s,
        event_type: event_type.to_s,
        occurred_at: Time.zone.parse(occurred_at.to_s),
        metadata: metadata.deep_stringify_keys
      )
    rescue StandardError => e
      Rails.logger.error("[OptionsBuying::TelemetrySinkJob] #{e.class} - #{e.message}")
      raise
    end
  end
end
