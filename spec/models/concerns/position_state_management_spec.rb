# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PositionStateManagement do
  let(:tracker) { create(:position_tracker, :pending) }

  describe '#activate!' do
    it 'transitions from pending to active' do
      expect(tracker.status).to eq('pending')

      tracker.activate!

      expect(tracker.status).to eq('active')
      expect(tracker.reload.status).to eq('active')
    end

    it 'raises error for invalid transition' do
      exited_tracker = create(:position_tracker, :exited)

      expect do
        exited_tracker.activate!
      end.to raise_error(State::PositionStateMachine::InvalidStateTransitionError)
    end
  end

  describe '#exit!' do
    let(:active_tracker) { create(:position_tracker, :active, entry_price: BigDecimal('150.00')) }

    it 'transitions from active to exited' do
      expect(active_tracker.status).to eq('active')

      active_tracker.exit!(exit_price: BigDecimal('145.00'), exit_reason: 'stop_loss')

      expect(active_tracker.status).to eq('exited')
      expect(active_tracker.reload.status).to eq('exited')
    end

    it 'raises error for invalid transition' do
      pending_tracker = create(:position_tracker, :pending)

      expect do
        pending_tracker.exit!(exit_price: BigDecimal('145.00'))
      end.to raise_error(State::PositionStateMachine::InvalidStateTransitionError)
    end
  end

  describe '#cancel!' do
    it 'transitions from pending to cancelled' do
      tracker.cancel!(reason: 'manual_cancel')

      expect(tracker.status).to eq('cancelled')
      expect(tracker.reload.status).to eq('cancelled')
      expect(tracker.meta['cancellation_reason']).to eq('manual_cancel')
    end

    it 'transitions from active to cancelled' do
      active_tracker = create(:position_tracker, :active)
      active_tracker.cancel!(reason: 'risk_limit')

      expect(active_tracker.status).to eq('cancelled')
    end

    it 'raises error for invalid transition' do
      exited_tracker = create(:position_tracker, :exited)

      expect do
        exited_tracker.cancel!
      end.to raise_error(State::PositionStateMachine::InvalidStateTransitionError)
    end
  end

  describe '#can_transition_to?' do
    it 'returns true for valid transitions' do
      expect(tracker.can_transition_to?(:active)).to be true
      expect(tracker.can_transition_to?(:cancelled)).to be true
    end

    it 'returns false for invalid transitions' do
      expect(tracker.can_transition_to?(:exited)).to be false
    end

    it 'works with string states' do
      expect(tracker.can_transition_to?('active')).to be true
    end
  end

  describe '#valid_next_states' do
    it 'returns valid next states for pending' do
      expect(tracker.valid_next_states).to contain_exactly(:active, :cancelled)
    end

    it 'returns valid next states for active' do
      active_tracker = create(:position_tracker, :active)
      expect(active_tracker.valid_next_states).to contain_exactly(:exited, :cancelled)
    end

    it 'returns empty array for terminal states' do
      exited_tracker = create(:position_tracker, :exited)
      expect(exited_tracker.valid_next_states).to eq([])
    end
  end

  describe '#terminal_state?' do
    it 'returns false for non-terminal states' do
      expect(tracker.terminal_state?).to be false

      active_tracker = create(:position_tracker, :active)
      expect(active_tracker.terminal_state?).to be false
    end

    it 'returns true for terminal states' do
      exited_tracker = create(:position_tracker, :exited)
      expect(exited_tracker.terminal_state?).to be true

      cancelled_tracker = create(:position_tracker, :cancelled)
      expect(cancelled_tracker.terminal_state?).to be true
    end
  end

  describe '#state_display_name' do
    it 'returns human-readable state name' do
      expect(tracker.state_display_name).to eq('Pending')

      active_tracker = create(:position_tracker, :active)
      expect(active_tracker.state_display_name).to eq('Active')
    end
  end

  describe 'before_update callback' do
    it 'validates state transition on status change' do
      tracker.status = 'exited'

      expect { tracker.save! }.to raise_error(ActiveRecord::RecordInvalid, /Invalid transition/)
    end

    it 'allows valid state transitions' do
      tracker.status = 'active'

      expect { tracker.save! }.not_to raise_error
      expect(tracker.reload.status).to eq('active')
    end

    it 'does not validate if status unchanged' do
      tracker.quantity = 100

      expect { tracker.save! }.not_to raise_error
    end
  end
end
