# frozen_string_literal: true

module State
  # State machine for PositionTracker lifecycle management
  # Ensures valid state transitions and prevents invalid operations
  class PositionStateMachine
    STATES = {
      pending: :pending,
      active: :active,
      exited: :exited,
      cancelled: :cancelled
    }.freeze

    VALID_TRANSITIONS = {
      pending: [:active, :cancelled],
      active: [:exited, :cancelled],
      exited: [], # Terminal state
      cancelled: [] # Terminal state
    }.freeze

    class << self
      # Check if transition is valid
      # @param from_state [Symbol, String] Current state
      # @param to_state [Symbol, String] Target state
      # @return [Boolean]
      def valid_transition?(from_state, to_state)
        from = normalize_state(from_state)
        to = normalize_state(to_state)

        return false unless VALID_TRANSITIONS.key?(from)
        return false unless STATES.value?(to)

        VALID_TRANSITIONS[from].include?(to)
      end

      # Get valid transitions from a state
      # @param state [Symbol, String] Current state
      # @return [Array<Symbol>] Valid target states
      def valid_transitions_from(state)
        from = normalize_state(state)
        VALID_TRANSITIONS[from] || []
      end

      # Check if state is terminal (no further transitions)
      # @param state [Symbol, String] State to check
      # @return [Boolean]
      def terminal_state?(state)
        normalized = normalize_state(state)
        VALID_TRANSITIONS[normalized]&.empty? || false
      end

      # Validate state transition and raise if invalid
      # @param from_state [Symbol, String] Current state
      # @param to_state [Symbol, String] Target state
      # @raise [InvalidStateTransitionError] If transition is invalid
      def validate_transition!(from_state, to_state)
        return if valid_transition?(from_state, to_state)

        raise InvalidStateTransitionError,
              "Invalid transition from #{from_state} to #{to_state}. " \
              "Valid transitions from #{from_state}: #{valid_transitions_from(from_state).join(', ')}"
      end

      # Get state display name
      # @param state [Symbol, String] State
      # @return [String] Human-readable state name
      def display_name(state)
        normalized = normalize_state(state)
        normalized.to_s.humanize
      end

      private

      def normalize_state(state)
        state.to_s.downcase.to_sym
      end
    end

    # Custom error for invalid state transitions
    class InvalidStateTransitionError < StandardError; end
  end
end
