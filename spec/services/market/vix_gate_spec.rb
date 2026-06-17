# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::VixGate do
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_cache)
    memory_cache.clear

    allow(AlgoConfig).to receive(:fetch).and_return(
      market: {
        vix_gate: {
          enabled: true,
          security_id: '21',
          segment: 'IDX_I',
          entry_ceiling: 20.0,
          force_exit_above: 22.0
        }
      }
    )
  end

  describe '.entry_allowed?' do
    context 'when fail-closed and VIX has not been evaluated' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          market: { vix_gate: { enabled: true, fail_closed_entries: true } }
        )
      end

      it 'blocks entries' do
        expect(described_class.entry_allowed?).to be(false)
        expect(described_class.evaluated?).to be(false)
      end
    end

    context 'when fail-open and VIX has not been evaluated' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          market: { vix_gate: { enabled: true, fail_closed_entries: false } }
        )
      end

      it 'allows entries' do
        expect(described_class.entry_allowed?).to be(true)
      end
    end
  end

  describe '.evaluate!' do
    it 'locks entries when VIX is above ceiling' do
      allow(Live::TickCache).to receive(:ltp).and_return(21.5)

      described_class.evaluate!

      expect(described_class.entry_allowed?).to be(false)
      expect(described_class.force_exit_active?).to be(false)
    end

    it 'arms force-exit when VIX is above accelerator' do
      allow(Live::TickCache).to receive(:ltp).and_return(23.0)

      described_class.evaluate!

      expect(described_class.entry_allowed?).to be(false)
      expect(described_class.force_exit_active?).to be(true)
    end

    context 'when instrument is missing from DB' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DHANHQ_ENABLED').and_return('true')
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
        allow(Instrument).to receive_messages(find_by_sid_and_segment: nil, where: Instrument.none)
        allow(DhanHQ::Models::MarketFeed).to receive(:ltp).and_return(
          'status' => 'success',
          'data' => { 'IDX_I' => { '21' => { 'last_price' => 18.4 } } }
        )
      end

      it 'falls back to DhanHQ LTP API' do
        result = described_class.evaluate!

        expect(result).to eq(18.4)
        expect(described_class.entry_allowed?).to be(true)
      end
    end
  end
end
