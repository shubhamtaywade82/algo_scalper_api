# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::IvVolGateGuard do
  let(:index_cfg) { { key: 'NIFTY' } }
  let(:pick) { { symbol: 'NIFTY26APR22000CE', iv: current_iv } }
  let(:context) do
    {
      index_cfg: index_cfg,
      pick: pick,
      direction: :bullish
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        iv_vol_gate: {
          enabled: true,
          max_iv_rank: 0.80,
          min_iv_rank: 0.10
        }
      }
    )
    # Mock historical snapshots: min 12.0, max 18.0
    allow(IvSnapshot).to receive(:historical_iv).with(index_key: 'nifty', days: 30).and_return(
      [12.0, 13.0, 15.0, 16.0, 18.0]
    )
  end

  describe '.call' do
    context 'when current IV is in the sweet spot (IV Rank = 50%)' do
      let(:current_iv) { 15.0 }

      it 'passes the guard' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when current IV is too high (IV Rank = 100%)' do
      let(:current_iv) { 20.0 }

      it 'blocks the entry' do
        result = described_class.call(context)
        expect(result).to be_a(Hash)
        expect(result[:blocked]).to include('IV Rank (100.0%) is too high')
      end
    end

    context 'when current IV is too low (IV Rank = 0%)' do
      let(:current_iv) { 10.0 }

      it 'blocks the entry' do
        result = described_class.call(context)
        expect(result).to be_a(Hash)
        expect(result[:blocked]).to include('IV Rank (0.0%) is too low')
      end

      context 'with symbol-specific min_iv_rank override' do
        let(:index_cfg) { { key: 'NIFTY', risk_model: { min_iv_rank: 0.0 } } }

        it 'passes when IV rank meets the symbol-specific threshold' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end
    end
  end
end
