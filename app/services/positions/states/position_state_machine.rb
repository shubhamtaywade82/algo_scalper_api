# frozen_string_literal: true

module Positions
  module States
    # Wraps a PositionTracker and provides:
    #
    #   • A concrete State object for the current DB status
    #   • Transition validation (TRANSITIONS table)
    #   • Lifecycle hooks (on_exit / on_enter) fired during transitions
    #   • Convenience predicate helpers (active?, closed?, etc.)
    #
    # DB states (PositionTracker enum): pending | active | exited | cancelled
    #
    # NOTE: TrailingState and ExitPendingState exist as domain concepts but are
    # NOT separate DB states — trailing is tracked via tracker.meta and
    # exit_pending via tracker.exit_requested_at. The state machine therefore
    # works with the 4 DB-backed states only.
    #
    # The machine is READ-ONLY with respect to the database — it never writes
    # to the tracker itself. Callers persist the new status via mark_active! etc.
    #
    # Idempotency: transition_to! is a no-op when already in the target state,
    # matching WebSocket handler semantics (fills can replay on reconnect).
    #
    # Usage:
    #   sm = PositionStateMachine.new(tracker)
    #   sm.state                          # => #<ActiveState …>
    #   sm.can?(:trail)                   # => true
    #   sm.valid_transition?(:exited)     # => true
    #   sm.transition_to!(:exited)        # fires on_exit + on_enter hooks
    #   sm.available_transitions          # => [:exited, :cancelled]
    class PositionStateMachine
      # ── Allowed state transitions (DB states only) ────────────────────────
      TRANSITIONS = {
        pending: %i[active cancelled],
        active: %i[exited cancelled],
        exited: [],
        cancelled: []
      }.freeze

      # ── DB status → State class mapping ──────────────────────────────────
      STATE_CLASSES = {
        pending: PendingState,
        active: ActiveState,
        exited: ClosedState,
        cancelled: ClosedState
      }.freeze

      attr_reader :tracker

      def initialize(tracker)
        @tracker = tracker
      end

      # ── State access ──────────────────────────────────────────────────────

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

      # ── Capability checks ─────────────────────────────────────────────────

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

      # ── Transition logic ──────────────────────────────────────────────────

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
      # Idempotent: no-op when already in the target state (supports WebSocket
      # replay semantics — fill events can arrive more than once).
      # NOTE: Does NOT persist anything — caller must update the DB status.
      #
      # @param to_state [Symbol, String]
      # @raise [IllegalTransitionError] if transition is not allowed
      def transition_to!(to_state)
        to_sym = to_state.to_sym
        return if current_status == to_sym  # already there — idempotent no-op

        assert_transition!(to_sym)
        state.on_exit
        STATE_CLASSES.fetch(to_sym, BaseState).new(tracker).on_enter
      end

      # ── Convenience predicates ────────────────────────────────────────────
      def pending?  = current_status == :pending
      def active?   = current_status == :active
      def closed?   = %i[exited cancelled].include?(current_status)

      # ── Errors ────────────────────────────────────────────────────────────
      class IllegalTransitionError < StandardError; end
    end
  end
end
