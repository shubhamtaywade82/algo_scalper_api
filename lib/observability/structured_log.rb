# frozen_string_literal: true

require 'json'

module Observability
  module StructuredLog
    module_function

    def info(event:, payload: {})
      emit(level: :info, event: event, payload: payload)
    end

    def warn(event:, payload: {})
      emit(level: :warn, event: event, payload: payload)
    end

    def error(event:, payload: {})
      emit(level: :error, event: event, payload: payload)
    end

    def emit(level:, event:, payload: {})
      entry = {
        event: event,
        timestamp: Time.current.iso8601
      }.merge(payload)

      Rails.logger.public_send(level, entry.to_json)
    rescue StandardError => e
      Rails.logger.error("[StructuredLog] #{e.class} - #{e.message}")
    end
  end
end
