# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::VixGateGuard do
  let(:context) { { index_cfg: { key: 'NIFTY' } } }

  context 'when VIX gate is disabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(market: { vix_gate: { enabled: false } })
    end

    it 'passes without checking VIX' do
      allow(Market::VixGate).to receive(:entry_allowed?)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      expect(Market::VixGate).not_to have_received(:entry_allowed?)
    end
  end

  context 'when VIX gate is enabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        market: { vix_gate: { enabled: true, entry_ceiling: 20.0 } }
      )
    end

    context 'when entry is allowed' do
      before do
        allow(Market::VixGate).to receive(:entry_allowed?).and_return(true)
      end

      it 'passes' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when VIX is above ceiling' do
      before do
        allow(Market::VixGate).to receive_messages(entry_allowed?: false, current_ltp: 21.5)
      end

      it 'blocks entry' do
        result = described_class.call(context)

        expect(result[:blocked]).to include('India VIX gate')
        expect(result[:blocked]).to include('21.5')
        expect(result[:blocked]).to include('20.0')
      end
    end
  end
end
