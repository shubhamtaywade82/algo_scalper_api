# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_FNO', cooldown_sec: 0 } }
  let(:pick) { { symbol: 'NIFTY24MAR22000CE', security_id: '12345', segment: 'NSE_FNO', ltp: BigDecimal('150.0') } }
  let(:direction) { 'LONG' }
  let(:signal) { double(record_entry_outcome: true) } # rubocop:disable RSpec/VerifiedDoubles
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: 'NSE', segment: 'index', security_id: '13') }
  let(:ltp) { BigDecimal('150.0') }

  describe '.try_enter' do
    before do
      instrument
      # Generic pipeline pass
      allow(described_class.entry_guard_pipeline).to receive(:run).and_return(Entries::EntryGuardPipeline::PASS)

      # Mock order execution
      allow(Entries::OrderExecutionService).to receive(:call).and_return(instance_double(PositionTracker))
    end

    context 'when pipeline fails' do
      let(:blocked_reason) { 'pipeline_reason' }

      before do
        allow(described_class.entry_guard_pipeline).to receive(:run).and_return({ blocked: blocked_reason })
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

      context 'when quantity calculation fails' do
        it 'returns false when quantity is zero' do
          allow(Capital::Allocator).to receive(:qty_for).and_return(0)

          expect do
            result = described_class.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: :bullish
            )

            expect(result).to be false
          end.not_to change(PositionTracker, :count)
        end
      end
    end

    context 'when successful' do
      it 'enters and records success' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be true
        expect(signal).to have_received(:record_entry_outcome).with('entered')
      end
    end
  end

  describe Entries::Guards::ExposureGuard do
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
end
