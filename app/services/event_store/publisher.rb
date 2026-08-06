# frozen_string_literal: true

require 'json_schemer'

module EventStore
  # Append-only SMC / market events. Use event_type `signal` with the full contract for validation.
  class Publisher
    class << self
      def publish!(stream:, event_type:, correlation_id:, payload:, decision_id: nil, validate_contract: true)
        event_decision_id = decision_id || DecisionTrace.current_id
        payload_with_meta = payload.is_a?(Hash) ? payload.merge(decision_id: event_decision_id).compact : payload

        validate_contract!(payload_with_meta) if validate_contract && signal_event?(event_type)

        SmcEvent.create!(
          stream: stream,
          event_type: event_type,
          correlation_id: correlation_id,
          payload: payload_with_meta
        )
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("[EventStore::Publisher] #{e.class} - #{e.message}")
        raise
      end

      def validate_contract!(payload)
        return if schema.valid?(payload)

        raise ArgumentError, '[EventStore::Publisher] Payload failed schemas/smc_trading_signal.json validation'
      end

      def schema
        @schema ||= JSONSchemer.schema(Rails.root.join('schemas/smc_trading_signal.json'))
      end

      def signal_event?(event_type)
        event_type.to_s == 'signal'
      end
    end
  end
end
