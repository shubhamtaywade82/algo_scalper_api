# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::OptionVolumeVelocityGuard do
  let(:index_cfg) { { key: 'NIFTY' } }
  let(:pick) { { symbol: 'NIFTY26APR22000CE', security_id: '55112', strike: 22_000.0, expiry_date: Date.current } }
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
        volume_velocity_gate: { enabled: true }
      }
    )
    # Mock DTE resolver and baseline
    allow(Trading::DteResolver).to receive(:days_to_expiry).and_return(7)
    allow(Trading::DteParameterResolver).to receive(:volume_velocity_multiplier).and_return(2.0)
    allow(OptionsBuying::StateStore).to receive(:volume_threshold_baseline).with('55112').and_return(100.0)
  end

  describe '.call' do
    context 'when volume velocity is high enough' do
      before do
        # volume_delta = 250
        allow(OptionsBuying::StateStore).to receive(:stream_window).with('55112').and_return(
          [{ vol: 1000 }, { vol: 1100 }, { vol: 1250 }]
        )
      end

      it 'passes the guard' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when volume velocity is too low' do
      before do
        # volume_delta = 50
        allow(OptionsBuying::StateStore).to receive(:stream_window).with('55112').and_return(
          [{ vol: 1000 }, { vol: 1020 }, { vol: 1050 }]
        )
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to be_a(Hash)
        expect(result[:blocked]).to include('volume velocity too low')
      end
    end
  end
end
