# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_FNO', cooldown_sec: 0 } }
  let(:pick) { { symbol: 'NIFTY24MAR22000CE', security_id: '12345', segment: 'NSE_FNO' } }
  let(:direction) { 'LONG' }
  let(:signal) { double('Signal', record_entry_outcome: true) }
  let(:instrument) { instance_double(Instrument, id: 1, symbol_name: 'NIFTY', exchange_segment: 'NSE_IDX') }
  let(:ltp) { BigDecimal('150.0') }
  
  before do
    # Generic pipeline pass
    allow(Entries::EntryGuard.entry_guard_pipeline).to receive(:run).and_return(Entries::EntryGuardPipeline::PASS)
    
    # Mock order execution
    allow(Entries::OrderExecutionService).to receive(:call).and_return(instance_double(PositionTracker))
  end

  describe '.build_base_meta' do
    subject(:meta) { described_class.send(:build_base_meta, index_cfg: index_cfg, pick: pick, direction: direction) }

    it 'stamps the effective config version on the tracker meta' do
      expect(meta[:config_version]).to include(:hash)
    end

    it 'pins a config snapshot for the position' do
      expect(meta[:config_snapshot]).to be_a(Hash).and(include(:risk))
    end

    it 'excludes credential sections from the pinned snapshot' do
      expect(meta[:config_snapshot].keys).not_to include(:dhanhq, :telegram, :ai)
    end
  end

  describe '.try_enter' do
    context 'when pipeline fails' do
      let(:blocked_reason) { 'pipeline_reason' }
      before do
        allow(Entries::EntryGuard.entry_guard_pipeline).to receive(:run).and_return({ blocked: blocked_reason })
      end

      it 'blocks entry and records outcome' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be false
        expect(signal).to have_received(:record_entry_outcome).with('blocked', blocked_reason)
      end
    end

    context 'when order execution fails' do
      before do
        allow(Entries::OrderExecutionService).to receive(:call).and_return({ error: 'order_failed' })
      end

      it 'blocks entry and records outcome' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be false
        expect(signal).to have_received(:record_entry_outcome).with('blocked', 'order_failed')
      end
    end

    context 'when successful' do
      it 'enters and records success' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be true
        expect(signal).to have_received(:record_entry_outcome).with('entered')
      end
    end
  end
end

RSpec.describe Entries::Guards::ExposureGuard do
  describe '.exposure_ok?' do
    let(:db_instrument) { create(:instrument) }

    it 'returns true when under limit' do
      expect(described_class.exposure_ok?(instrument: db_instrument, side: 'long_ce', max_same_side: 3)).to be true
    end

    it 'returns false when at limit' do
      create_list(:position_tracker, 2, instrument: db_instrument, status: 'active', side: 'long_ce', segment: 'NSE_FNO', security_id: '999')
      expect(described_class.exposure_ok?(instrument: db_instrument, side: 'long_ce', max_same_side: 2)).to be false
    end
  end
end
