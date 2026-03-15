# frozen_string_literal: true

module Positions
  module States
    # Wraps a PositionTracker and provides:
    #
    #   • A concrete State object for the current DB status
    #   • Transition validation (TRANSITIONS table)
    #   • Lifecycle hooks (on_exit / on_enter) fired during transitions
    #   • Convenience predicate helpers (active?, trailing?, etc.)
    #
    # The machine is READ-ONLY with respect to the database — it never
    # writes to the tracker itself.  Callers are responsible for persisting
    # the new status via the appropriate tracker method (mark_active! etc.).
    #
    # Usage:
    #   sm = PositionStateMachine.new(tracker)
    #   sm.state                          # => #<ActiveState …>
    #   sm.can?(:trail)                   # => true
    #   sm.valid_transition?(:trailing)   # => true
    #   sm.transition_to!(:trailing)      # fires on_exit + on_enter hooks
    #   sm.available_transitions          # => [:trailing, :exit_pending, :exited, :cancelled]
    class PositionStateMachine
      # ── Allowed state transitions ──────────────────────────────────────────
      TRANSITIONS = {
        pending:      %i[active cancelled],
        active:       %i[trailing exit_pending exited cancelled],
        trailing:     %i[exit_pending exited cancelled],
        exit_pending: %i[exited cancelled],
        exited:       [],
        cancelled:    []
      }.freeze

      # ── DB status → State class mapping ───────────────────────────────────
      STATE_CLASSES = {
        pending:      PendingState,
        active:       ActiveState,
        trailing:     TrailingState,
        exit_pending: ExitPendingState,
        exited:       ClosedState,
        cancelled:    ClosedState
      }.freeze

      attr_reader :tracker

      def initialize(tracker)
        @tracker = tracker
      end

      # ── State access ───────────────────────────────────────────────────────

      # Returns the concrete State object for the current tracker status.
      # @return [BaseState]
      def state
        STATE_CLASSES.fetch(current_status, BaseState).new(tracker)
      end

      # The current status as a symbol, taken directly from the tracker.
      # @return [Symbol]
      def current_status
        tracker.status.to_sym
      end

      # ── Capability checks ──────────────────────────────────────────────────

      # Delegates capability check to the current state object.
      #
      # @param capability [Symbol] e.g. :trail, :request_exit, :activate, :close
      # @return [Boolean]
      def can?(capability)
        state.public_send(:"can_#{capability}?")
      rescue NoMethodError
        false
      end

      def terminal?
        state.terminal?
      end

      # ── Transition logic ───────────────────────────────────────────────────

      # Returns the list of reachable next states from the current status.
      # @return [Array<Symbol>]
      def available_transitions
        TRANSITIONS.fetch(current_status, [])
      end

      # Returns true if the given state is a legal next state.
      # @param to_state [Symbol, String]
      # @return [Boolean]
      def valid_transition?(to_state)
        available_transitions.include?(to_state.to_sym)
      end

      # Raises IllegalTransitionError if the transition is not allowed.
      # @param to_state [Symbol, String]
      # @raise [IllegalTransitionError]
      def assert_transition!(to_state)
        return if valid_transition?(to_state)

        raise IllegalTransitionError,
              "Cannot transition '#{tracker.order_no}' " \
              "from #{current_status} → #{to_state} " \
              "(allowed: #{available_transitions.join(', ')})"
      end

      # Fires lifecycle hooks for the transition.
      # NOTE: Does NOT persist anything — caller must update the DB status.
      #
      # @param to_state [Symbol, String]
      # @raise [IllegalTransitionError] if transition is not allowed
      def transition_to!(to_state)
        to_sym = to_state.to_sym
        assert_transition!(to_sym)

        state.on_exit
        STATE_CLASSES.fetch(to_sym, BaseState).new(tracker).on_enter
      end

      # ── Convenience predicates ─────────────────────────────────────────────
      def pending?      = current_status == :pending
      def active?       = current_status == :active
      def trailing?     = current_status == :trailing
      def exit_pending? = current_status == :exit_pending
      def closed?       = %i[exited cancelled].include?(current_status)

      # ── Errors ─────────────────────────────────────────────────────────────
      class IllegalTransitionError < StandardError; end
    end
  end
end
