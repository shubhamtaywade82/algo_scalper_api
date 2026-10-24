# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::StrikeCooldownGuard do
  let(:security_id) { 'SEC123' }
  let(:context) { { pick: { security_id: security_id } } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      strike_cooldown_guard: {
        enabled: true,
        after_any_exit: true,
        cooldown_minutes: 30,
        loss_cooldown_minutes: 45
      },
      paper_trading: { enabled: true }
    )
  end

  describe '.call' do
    context 'when same strike exited recently' do
      it 'blocks re-entry after a winning exit' do
        allow(described_class).to receive(:recent_exit).with(security_id).and_return([5.minutes.ago, 500.0])

        result = described_class.call(context)

        expect(result[:blocked]).to include('strike cooldown active')
      end

      it 'uses longer cooldown after a loss' do
        allow(described_class).to receive(:recent_exit).with(security_id).and_return([35.minutes.ago, -2_000.0])

        result = described_class.call(context)

        expect(result[:blocked]).to include('strike cooldown active')
      end
    end

    context 'when cooldown window elapsed' do
      it 'passes' do
        allow(described_class).to receive(:recent_exit).with(security_id).and_return([50.minutes.ago, -2_000.0])

        expect(described_class.call(context)).to eq(Entries::Guards::BaseGuard::PASS)
      end
    end
  end
end
