# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::ChainConfirmationGuard do
  let(:index_cfg) { { key: 'NIFTY' } }
  let(:pick) { { strike: 24800.0, type: 'CE', security_id: '24800CE' } }
  let(:context) { { index_cfg: index_cfg, pick: pick, direction: :bullish } }

  let(:default_config) do
    {
      risk: {
        chain_confirmation_gate: {
          enabled: true,
          min_oi_change: 0,
          min_iv: 8.0,
          max_iv: 45.0,
          min_delta: 0.25,
          max_delta: 0.75
        }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(default_config)
  end

  def stub_snapshot(legs)
    allow(Options::ChainWatchRegistry).to receive(:snapshot_for).with('NIFTY').and_return(
      { index_key: 'NIFTY', spot: 24800.0, atm_strike: 24800.0, chain_stale: false, legs: legs }
    )
  end

  describe '.call' do
    context 'when OI, IV, and delta are all within configured bands' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: 500, iv: 15.0, delta: 0.5 }])
      end

      it 'passes' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when OI change is below the minimum (no fresh buildup)' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: -200, iv: 15.0, delta: 0.5 }])
      end

      it 'blocks with an OI reason' do
        result = described_class.call(context)
        expect(result[:blocked]).to include('OI change')
      end
    end

    context 'when IV is above the configured max' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: 500, iv: 60.0, delta: 0.5 }])
      end

      it 'blocks with an IV reason' do
        result = described_class.call(context)
        expect(result[:blocked]).to include('IV')
      end
    end

    context 'when delta is outside the configured band' do
      before do
        stub_snapshot([{ strike: 24800.0, type: 'CE', oi_change: 500, iv: 15.0, delta: 0.9 }])
      end

      it 'blocks with a delta reason' do
        result = described_class.call(context)
        expect(result[:blocked]).to include('delta')
      end
    end

    context 'when the guard is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { chain_confirmation_gate: { enabled: false } })
      end

      it 'passes without checking anything' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when no snapshot is registered for the index' do
      before { allow(Options::ChainWatchRegistry).to receive(:snapshot_for).with('NIFTY').and_return(nil) }

      it 'fails open' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when the snapshot is stale' do
      before do
        allow(Options::ChainWatchRegistry).to receive(:snapshot_for).with('NIFTY').and_return(
          { chain_stale: true, legs: [{ strike: 24800.0, type: 'CE', oi_change: -999, iv: 99.0, delta: 0.99 }] }
        )
      end

      it 'fails open even though the leg data would otherwise block' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when no leg in the snapshot matches the picked strike/type' do
      before { stub_snapshot([{ strike: 25000.0, type: 'CE', oi_change: 500, iv: 15.0, delta: 0.5 }]) }

      it 'fails open' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when Options::ChainWatchRegistry raises' do
      before { allow(Options::ChainWatchRegistry).to receive(:snapshot_for).and_raise(StandardError, 'boom') }

      it 'fails open' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
