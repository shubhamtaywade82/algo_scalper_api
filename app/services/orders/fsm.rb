# frozen_string_literal: true

module Orders
  # Explicit Finite State Machine for order state management & auditability.
  class Fsm
    STATES = %i[
      created submitting submitted acknowledged partially_filled
      filled cancel_pending cancelled rejected unknown reconciled
    ].freeze

    TRANSITIONS = {
      created: %i[submitting cancelled rejected],
      submitting: %i[submitted acknowledged rejected unknown],
      submitted: %i[acknowledged partially_filled filled cancel_pending cancelled rejected unknown],
      acknowledged: %i[partially_filled filled cancel_pending cancelled rejected unknown active],
      active: %i[reconciled exited cancelled filled cancel_pending unknown],
      partially_filled: %i[partially_filled filled cancel_pending cancelled unknown],
      cancel_pending: %i[cancelled acknowledged unknown reconciled],
      rejected: [].freeze,
      filled: [].freeze,
      cancelled: [].freeze,
      unknown: %i[reconciled cancelled filled rejected acknowledged],
      reconciled: %i[filled cancelled rejected acknowledged]
    }.freeze

    class InvalidTransitionError < StandardError; end

    class << self
      def valid_transition?(from_state, to_state)
        from = from_state.to_s.downcase.to_sym
        to = to_state.to_s.downcase.to_sym
        return true if from == to

        allowed = TRANSITIONS[from] || []
        allowed.include?(to)
      end

      def transition!(order_or_tracker, target_state, metadata: {})
        from_state = extract_state(order_or_tracker)
        to_state = target_state.to_s.downcase.to_sym

        unless valid_transition?(from_state, to_state)
          raise InvalidTransitionError, "Invalid order FSM transition from #{from_state} to #{to_state}"
        end

        apply_transition(order_or_tracker, from_state, to_state, metadata)
      end

      private

      def extract_state(record)
        return record.to_s.downcase.to_sym if record.is_a?(Symbol) || record.is_a?(String)
        return record.status.to_s.downcase.to_sym if record.respond_to?(:status) && record.status.present?

        :created
      end

      def apply_transition(record, from_state, to_state, metadata)
        payload = {
          from_state: from_state,
          to_state: to_state,
          transitioned_at: Time.current.iso8601(3),
          metadata: metadata
        }

        if record.respond_to?(:meta) && record.respond_to?(:update!)
          meta_hash = (record.meta.is_a?(Hash) ? record.meta : {}).dup
          history = Array(meta_hash['fsm_history'])
          history << payload
          meta_hash['fsm_history'] = history.last(20)

          record.update!(meta: meta_hash)
        end

        order_id = record.respond_to?(:order_no) ? record.order_no.to_s : SecureRandom.hex(4)

        EventStore::Publisher.publish!(
          stream: 'orders',
          event_type: 'trading.order.fsm_transitioned',
          correlation_id: order_id,
          payload: payload,
          decision_id: EventStore::DecisionTrace.current_id
        )

        to_state
      end
    end
  end
end
