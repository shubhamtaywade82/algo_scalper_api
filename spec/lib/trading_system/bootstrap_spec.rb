# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSystem::Bootstrap do
  describe '.boot_market_gates!' do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_cache)
      memory_cache.clear
    end

    context 'when VIX gate is enabled and LTP is available' do
      before do
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
        allow(Live::TickCache).to receive(:ltp).and_return(21.5)
      end

      it 'evaluates the gate and returns VIX LTP' do
        result = described_class.boot_market_gates!

        expect(result).to eq(21.5)
        expect(Market::VixGate.entry_allowed?).to be(false)
      end
    end

    context 'when VIX LTP is unavailable' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          market: { vix_gate: { enabled: true, security_id: '21', segment: 'IDX_I' } }
        )
        allow(Live::TickCache).to receive(:ltp).and_return(nil)
        allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nil)
      end

      it 'returns nil without raising' do
        expect(described_class.boot_market_gates!).to be_nil
      end
    end
  end

  describe '.build_supervisor' do
    it 'registers a ChainWatchService for each of NIFTY, BANKNIFTY, SENSEX' do
      supervisor = described_class.build_supervisor
      registered = supervisor.instance_variable_get(:@services)

      expect(registered.keys).to include(:chain_watch_nifty, :chain_watch_banknifty, :chain_watch_sensex)
      expect(registered[:chain_watch_nifty]).to be_a(Options::ChainWatchService)
      expect(registered[:chain_watch_banknifty]).to be_a(Options::ChainWatchService)
      expect(registered[:chain_watch_sensex]).to be_a(Options::ChainWatchService)
    end
  end
end
