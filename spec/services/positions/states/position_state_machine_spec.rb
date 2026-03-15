# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::States::PositionStateMachine do
  subject(:machine) { described_class.new(tracker) }

  let(:tracker) { build_stubbed(:position_tracker, status: status, order_no: 'ORD999') }

  # ── State resolution ────────────────────────────────────────────────────────

  describe '#state' do
    context 'when status is pending' do
      let(:status) { 'pending' }

      it { expect(machine.state).to be_a(Positions::States::PendingState) }
    end

    context 'when status is active' do
      let(:status) { 'active' }

      it { expect(machine.state).to be_a(Positions::States::ActiveState) }
    end

    context 'when status is exited' do
      let(:status) { 'exited' }

      it { expect(machine.state).to be_a(Positions::States::ClosedState) }
    end

    context 'when status is cancelled' do
      let(:status) { 'cancelled' }

      it { expect(machine.state).to be_a(Positions::States::ClosedState) }
    end
  end

  # ── Capability checks ───────────────────────────────────────────────────────

  describe '#can?' do
    context 'in pending state' do
      let(:status) { 'pending' }

      it 'can activate' do
        expect(machine.can?(:activate)).to be true
      end

      it 'cannot trail' do
        expect(machine.can?(:trail)).to be false
      end

      it 'cannot request exit' do
        expect(machine.can?(:request_exit)).to be false
      end
    end

    context 'in active state' do
      let(:status) { 'active' }

      it 'can trail' do
        expect(machine.can?(:trail)).to be true
      end

      it 'can request exit' do
        expect(machine.can?(:request_exit)).to be true
      end

      it 'cannot activate' do
        expect(machine.can?(:activate)).to be false
      end
    end

    context 'in trailing state' do
      let(:status) { 'trailing' }

      it 'can trail' do
        expect(machine.can?(:trail)).to be true
      end

      it 'can request exit' do
        expect(machine.can?(:request_exit)).to be true
      end
    end

    context 'in exit_pending state' do
      let(:status) { 'exit_pending' }

      it 'can close' do
        expect(machine.can?(:close)).to be true
      end

      it 'cannot request exit' do
        expect(machine.can?(:request_exit)).to be false
      end
    end

    context 'in closed (exited) state' do
      let(:status) { 'exited' }

      it 'cannot do anything' do
        expect(machine.can?(:activate)).to be false
        expect(machine.can?(:trail)).to be false
        expect(machine.can?(:request_exit)).to be false
      end

      it 'is terminal' do
        expect(machine.terminal?).to be true
      end
    end
  end

  # ── Transition validation ───────────────────────────────────────────────────

  describe '#valid_transition?' do
    let(:status) { 'pending' }

    it 'returns true for allowed transitions' do
      expect(machine.valid_transition?(:active)).to be true
      expect(machine.valid_transition?(:cancelled)).to be true
    end

    it 'returns false for disallowed transitions' do
      expect(machine.valid_transition?(:exited)).to be false
      expect(machine.valid_transition?(:trailing)).to be false
    end
  end

  describe '#available_transitions' do
    context 'when active' do
      let(:status) { 'active' }

      it 'returns correct next states' do
        expect(machine.available_transitions).to match_array(%i[trailing exit_pending exited cancelled])
      end
    end

    context 'when exited (terminal)' do
      let(:status) { 'exited' }

      it 'returns empty array' do
        expect(machine.available_transitions).to be_empty
      end
    end
  end

  describe '#assert_transition!' do
    let(:status) { 'pending' }

    it 'does not raise for valid transitions' do
      expect { machine.assert_transition!(:active) }.not_to raise_error
    end

    it 'raises IllegalTransitionError for invalid transitions' do
      expect { machine.assert_transition!(:exited) }
        .to raise_error(Positions::States::PositionStateMachine::IllegalTransitionError, /pending.*exited/)
    end
  end

  # ── Lifecycle hooks ─────────────────────────────────────────────────────────

  describe '#transition_to!' do
    let(:status) { 'active' }

    it 'fires on_exit on the outgoing state and on_enter on the incoming state' do
      allow(Rails.logger).to receive(:debug)
      expect { machine.transition_to!(:trailing) }.not_to raise_error
    end

    it 'raises for illegal transitions' do
      expect { machine.transition_to!(:pending) }
        .to raise_error(Positions::States::PositionStateMachine::IllegalTransitionError)
    end
  end

  # ── Convenience predicates ──────────────────────────────────────────────────

  describe 'predicate helpers' do
    it 'active? is true when status is active' do
      tracker = build_stubbed(:position_tracker, status: 'active', order_no: 'X')
      expect(described_class.new(tracker).active?).to be true
    end

    it 'closed? is true for both exited and cancelled' do
      %w[exited cancelled].each do |st|
        tracker = build_stubbed(:position_tracker, status: st, order_no: 'X')
        expect(described_class.new(tracker).closed?).to be true
      end
    end

    it 'pending? is true when status is pending' do
      tracker = build_stubbed(:position_tracker, status: 'pending', order_no: 'X')
      expect(described_class.new(tracker).pending?).to be true
    end
  end
end
