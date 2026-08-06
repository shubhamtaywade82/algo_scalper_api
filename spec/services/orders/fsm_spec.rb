# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Fsm do
  describe '.valid_transition?' do
    it 'returns true for valid transitions' do
      expect(described_class.valid_transition?(:created, :submitting)).to be true
      expect(described_class.valid_transition?(:submitting, :acknowledged)).to be true
      expect(described_class.valid_transition?(:acknowledged, :filled)).to be true
    end

    it 'returns false for invalid transitions' do
      expect(described_class.valid_transition?(:filled, :submitting)).to be false
      expect(described_class.valid_transition?(:cancelled, :filled)).to be false
    end
  end

  describe '.transition!' do
    let(:tracker) { create(:position_tracker, status: 'active') }

    it 'raises InvalidTransitionError for illegal transitions' do
      expect do
        described_class.transition!(tracker, :submitting)
      end.to raise_error(Orders::Fsm::InvalidTransitionError)
    end

    it 'publishes transition event on valid transition' do
      allow(EventStore::Publisher).to receive(:publish!)
      expect(described_class.transition!(:submitting, :submitted)).to eq(:submitted)
      expect(EventStore::Publisher).to have_received(:publish!).with(
        stream: 'orders',
        event_type: 'trading.order.fsm_transitioned',
        correlation_id: anything,
        payload: hash_including(from_state: :submitting, to_state: :submitted),
        decision_id: anything
      )
    end
  end
end
