# frozen_string_literal: true

module Policies
  # Determines whether a position should be exited right now.
  #
  # Delegates to Live::UnifiedExitChecker for the full priority-ordered
  # evaluation (stop-loss → take-profit → trailing → time-based …) but
  # exposes the clean Policy interface so callers stay decoupled from the
  # checker internals.
  #
  # NOTE: `permitted?` returns TRUE when an exit SHOULD happen (i.e. a
  # condition is met), matching the "is this action allowed?" contract
  # of the base class but applied in the exit direction.
  #
  # Usage:
  #   policy = ExitPolicy.new(tracker: tracker)
  #   policy.permitted?     # => true  (exit condition met)
  #   policy.exit_reason    # => "STOP_LOSS"
  #   policy.exit_path      # => "stop_loss"
  #   policy.pnl_pct        # => -12.5  (percentage)
  class ExitPolicy < BasePolicy
    attr_reader :tracker

    def initialize(tracker:)
      @tracker  = tracker
      @decision = nil
    end

    # Returns true when an exit condition is triggered.
    def permitted?
      decision[:exit] == true
    end

    def reasons
      permitted? ? [decision[:reason]].compact : []
    end

    # The exit reason code (e.g. "STOP_LOSS", "TRAILING_STOP").
    # @return [String, nil]
    def exit_reason
      decision[:reason]
    end

    # The exit path identifier used for trade telemetry.
    # @return [String, nil]
    def exit_path
      decision[:path]
    end

    # PnL percentage at the time the decision was evaluated.
    # @return [Float, nil]
    def pnl_pct
      decision[:pnl_pct]
    end

    private

    def decision
      @decision ||= Live::UnifiedExitChecker.check_exit_conditions(tracker) || { exit: false }
    rescue StandardError => e
      Rails.logger.error("[ExitPolicy] check_exit_conditions failed for #{tracker&.order_no}: #{e.message}")
      { exit: false }
    end
  end
end
