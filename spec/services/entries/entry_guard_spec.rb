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
    allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
    allow_any_instance_of(Policies::EntryPolicy).to receive(:permitted?).and_return(true)
    allow(Entries::EntryGuard.entry_guard_pipeline).to receive(:run).and_return(Entries::EntryGuardPipeline::PASS)
    allow(Entries::EntryGuard).to receive(:enforce_structure_entry_gate).and_return({ bos_id: '123' })
    allow(Trading::InstrumentExecutionProfile).to receive(:for).and_return({
      max_lots_by_permission: { scale_ready: 10 },
      allow_execution_only: true
    })
    allow(Trading::LotCalculator).to receive(:lot_size_for).and_return(50)
    allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(10)
    allow(Capital::Allocator).to receive(:qty_for).and_return(500)
    allow_any_instance_of(Policies::RiskPolicy).to receive(:permitted?).and_return(true)
    
    # Mocking self.resolve_entry_ltp
    allow(Entries::EntryGuard).to receive(:resolve_entry_ltp).and_return(ltp)
    
    # Mock orders
    allow(Orders.config).to receive(:gateway).and_return(double('Gateway'))
    
    # Mocking PlaceOrderCommand
    place_result = double('Result', success?: true, payload: { raw: { order_id: 'ORD123' } })
    allow_any_instance_of(Orders::Commands::PlaceOrderCommand).to receive(:call).and_return(place_result)
    
    # Mocking tracker creation
    allow(Entries::EntryGuard).to receive(:create_tracker!).and_return(instance_double(PositionTracker))
  end

  describe '.try_enter' do
    context 'when drawdown guard is triggered' do
      before { allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(true) }

      it 'blocks entry' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be false
        expect(signal).to have_received(:record_entry_outcome).with('skipped', 'drawdown_guard_active')
      end
    end

    context 'when entry policy blocks' do
      before do
        policy = instance_double(Policies::EntryPolicy, permitted?: false, reasons: ['Too many trades'])
        allow(Policies::EntryPolicy).to receive(:new).and_return(policy)
      end

      it 'blocks entry' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be false
        expect(signal).to have_received(:record_entry_outcome).with('blocked', 'Too many trades')
      end
    end

    context 'when pipeline fails' do
      before { allow(Entries::EntryGuard.entry_guard_pipeline).to receive(:run).and_return({ blocked: 'pipeline_reason' }) }

      it 'blocks entry' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be false
        expect(signal).to have_received(:record_entry_outcome).with('blocked', 'pipeline_reason')
      end
    end

    context 'when successful' do
      it 'places order and returns true' do
        allow(Entries::EntryGuard.entry_guard_pipeline).to receive(:run) do |ctx|
          ctx[:instrument] = instrument
          ctx[:ltp] = ltp
          ctx[:side] = 'LONG'
          Entries::EntryGuardPipeline::PASS
        end
        
        allow(Entries::EntryGuard).to receive(:weekly_contract?).and_return(true)
        
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be true
        expect(signal).to have_received(:record_entry_outcome).with('entered')
      end
    end
  end

  describe '.exposure_ok?' do
    let(:db_instrument) { create(:instrument, segment: :derivatives) }

    it 'returns true when under limit' do
      expect(described_class.exposure_ok?(instrument: db_instrument, side: 'LONG', max_same_side: 3)).to be true
    end

    it 'returns false when at limit' do
      # Use NSE_FNO segment to avoid validation issues
      create_list(:position_tracker, 2, instrument: db_instrument, status: 'active', side: 'LONG', segment: 'NSE_FNO')
      expect(described_class.exposure_ok?(instrument: db_instrument, side: 'LONG', max_same_side: 2)).to be false
    end
  end
end
