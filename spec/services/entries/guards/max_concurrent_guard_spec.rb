# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::MaxConcurrentGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: 'NIFTY', max_concurrent_per_index: 2 }
      }
    end

    context 'when fewer than max concurrent positions exist' do
      before do
        allow(PositionTracker).to receive_message_chain(:active, :where, :count).and_return(1)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when max concurrent positions reached' do
      before do
        allow(PositionTracker).to receive_message_chain(:active, :where, :count).and_return(2)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /max_concurrent_positions/)
      end
    end

    context 'when max_concurrent_per_index not configured' do
      let(:context) { { index_cfg: { key: 'NIFTY' } } }

      it 'allows entry (no limit)' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end

