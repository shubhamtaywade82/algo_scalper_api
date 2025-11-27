# frozen_string_literal: true

module PositionStateManagement
  extend ActiveSupport::Concern

  included do
    # Validate state transitions before updating status
    before_update :validate_state_transition, if: :status_changed?
  end

  # Transition to active state
  # @return [Boolean] Success status
  def activate!
    State::PositionStateMachine.validate_transition!(status, :active)
    update!(status: :active)
  end

  # Transition to exited state
  # @param exit_price [BigDecimal, Float, nil] Exit price
  # @param exit_reason [String, nil] Exit reason
  # @return [Boolean] Success status
  def exit!(exit_price: nil, exit_reason: nil)
    State::PositionStateMachine.validate_transition!(status, :exited)
    mark_exited!(exit_price: exit_price, exit_reason: exit_reason)
  end

  # Transition to cancelled state
  # @param reason [String, nil] Cancellation reason
  # @return [Boolean] Success status
  def cancel!(reason: nil)
    State::PositionStateMachine.validate_transition!(status, :cancelled)
    update!(status: :cancelled, meta: (meta || {}).merge(cancellation_reason: reason))
  end

  # Check if state can transition to target state
  # @param target_state [Symbol, String] Target state
  # @return [Boolean]
  def can_transition_to?(target_state)
    State::PositionStateMachine.valid_transition?(status, target_state)
  end

  # Get valid next states
  # @return [Array<Symbol>]
  def valid_next_states
    State::PositionStateMachine.valid_transitions_from(status)
  end

  # Check if in terminal state
  # @return [Boolean]
  def terminal_state?
    State::PositionStateMachine.terminal_state?(status)
  end

  # Get state display name
  # @return [String]
  def state_display_name
    State::PositionStateMachine.display_name(status)
  end

  private

  def validate_state_transition
    return unless status_changed?

    from_state = status_was
    to_state = status

    unless State::PositionStateMachine.valid_transition?(from_state, to_state)
      errors.add(:status, "Invalid transition from #{from_state} to #{to_state}")
      throw(:abort)
    end
  end
end
