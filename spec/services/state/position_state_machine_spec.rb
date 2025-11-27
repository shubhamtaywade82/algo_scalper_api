# frozen_string_literal: true

require 'rails_helper'

RSpec.describe State::PositionStateMachine do
  describe '.valid_transition?' do
    it 'allows valid transitions' do
      expect(described_class.valid_transition?(:pending, :active)).to be true
      expect(described_class.valid_transition?(:pending, :cancelled)).to be true
      expect(described_class.valid_transition?(:active, :exited)).to be true
      expect(described_class.valid_transition?(:active, :cancelled)).to be true
    end

    it 'rejects invalid transitions' do
      expect(described_class.valid_transition?(:active, :pending)).to be false
      expect(described_class.valid_transition?(:exited, :active)).to be false
      expect(described_class.valid_transition?(:cancelled, :active)).to be false
    end

    it 'handles string states' do
      expect(described_class.valid_transition?('pending', 'active')).to be true
      expect(described_class.valid_transition?('active', 'exited')).to be true
    end

    it 'rejects invalid state names' do
      expect(described_class.valid_transition?(:pending, :invalid)).to be false
      expect(described_class.valid_transition?(:invalid, :active)).to be false
    end
  end

  describe '.valid_transitions_from' do
    it 'returns valid transitions for pending state' do
      transitions = described_class.valid_transitions_from(:pending)

      expect(transitions).to contain_exactly(:active, :cancelled)
    end

    it 'returns valid transitions for active state' do
      transitions = described_class.valid_transitions_from(:active)

      expect(transitions).to contain_exactly(:exited, :cancelled)
    end

    it 'returns empty array for terminal states' do
      expect(described_class.valid_transitions_from(:exited)).to eq([])
      expect(described_class.valid_transitions_from(:cancelled)).to eq([])
    end

    it 'handles string states' do
      transitions = described_class.valid_transitions_from('pending')

      expect(transitions).to contain_exactly(:active, :cancelled)
    end
  end

  describe '.terminal_state?' do
    it 'returns true for terminal states' do
      expect(described_class.terminal_state?(:exited)).to be true
      expect(described_class.terminal_state?(:cancelled)).to be true
    end

    it 'returns false for non-terminal states' do
      expect(described_class.terminal_state?(:pending)).to be false
      expect(described_class.terminal_state?(:active)).to be false
    end

    it 'handles string states' do
      expect(described_class.terminal_state?('exited')).to be true
      expect(described_class.terminal_state?('active')).to be false
    end
  end

  describe '.validate_transition!' do
    it 'does not raise for valid transitions' do
      expect do
        described_class.validate_transition!(:pending, :active)
      end.not_to raise_error
    end

    it 'raises InvalidStateTransitionError for invalid transitions' do
      expect do
        described_class.validate_transition!(:active, :pending)
      end.to raise_error(
        State::PositionStateMachine::InvalidStateTransitionError,
        /Invalid transition from active to pending/
      )
    end

    it 'includes valid transitions in error message' do
      expect do
        described_class.validate_transition!(:active, :pending)
      end.to raise_error(
        State::PositionStateMachine::InvalidStateTransitionError,
        /Valid transitions from active: exited, cancelled/
      )
    end
  end

  describe '.display_name' do
    it 'returns human-readable state name' do
      expect(described_class.display_name(:pending)).to eq('Pending')
      expect(described_class.display_name(:active)).to eq('Active')
      expect(described_class.display_name(:exited)).to eq('Exited')
      expect(described_class.display_name(:cancelled)).to eq('Cancelled')
    end

    it 'handles string states' do
      expect(described_class.display_name('pending')).to eq('Pending')
    end
  end

  describe 'STATES constant' do
    it 'defines all valid states' do
      expect(described_class::STATES).to include(
        pending: :pending,
        active: :active,
        exited: :exited,
        cancelled: :cancelled
      )
    end
  end
end
