# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::EntryPolicyGuard do
  describe '.call' do
    let(:context) do
      { index_cfg: { key: 'NIFTY' }, direction: :bullish }
    end
    let(:entry_policy_double) { instance_double(Policies::EntryPolicy) }

    before do
      allow(Policies::EntryPolicy).to receive(:new).and_return(entry_policy_double)
    end

    context 'when entry policy permits' do
      before do
        allow(entry_policy_double).to receive(:permitted?).and_return(true)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when entry policy does not permit' do
      before do
        allow(entry_policy_double).to receive_messages(permitted?: false, reasons: %w[outside_trading_hours daily_loss_limit_reached])
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /outside_trading_hours.*daily_loss_limit_reached/)
      end
    end

    context 'with missing direction' do
      let(:context) { { index_cfg: { key: 'NIFTY' } } }

      before do
        allow(entry_policy_double).to receive(:permitted?).and_return(true)
      end

      it 'allows entry (direction is optional in policy)' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
