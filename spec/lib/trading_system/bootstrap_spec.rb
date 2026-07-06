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
    before do
      allow(IndexConfigLoader).to receive(:load_indices).and_return(
        [
          { key: 'NIFTY', segment: 'IDX_I', sid: '13' },
          { key: 'BANKNIFTY', segment: 'IDX_I', sid: '25' },
          { key: 'SENSEX', segment: 'IDX_I', sid: '51' }
        ]
      )
    end

    it 'registers a ChainWatchService for each of NIFTY, BANKNIFTY, SENSEX' do
      supervisor = described_class.build_supervisor
      registered = supervisor.instance_variable_get(:@services)

      expect(registered.keys).to include(:chain_watch_nifty, :chain_watch_banknifty, :chain_watch_sensex)
      expect(registered[:chain_watch_nifty]).to be_a(Options::ChainWatchService)
      expect(registered[:chain_watch_banknifty]).to be_a(Options::ChainWatchService)
      expect(registered[:chain_watch_sensex]).to be_a(Options::ChainWatchService)
    end

    context 'when one index is disabled/unknown and ChainWatchService.new raises for it' do
      it 'still registers every other service instead of aborting the whole build' do
        original_new = Options::ChainWatchService.method(:new)
        allow(Options::ChainWatchService).to receive(:new) do |index_key:|
          raise "unknown_index:#{index_key}" if index_key == 'BANKNIFTY'

          original_new.call(index_key: index_key)
        end

        supervisor = nil
        expect { supervisor = described_class.build_supervisor }.not_to raise_error

        registered = supervisor.instance_variable_get(:@services)

        expect(registered.keys).to include(:chain_watch_nifty, :chain_watch_sensex)
        expect(registered.keys).not_to include(:chain_watch_banknifty)
        # Every non-chain-watch service should still be present.
        expect(registered.keys).to include(
          :market_feed, :tick_smc_ai, :options_buying_breakout, :options_buying_stream_consumer,
          :signal_scheduler, :risk_manager, :position_heartbeat, :order_router,
          :paper_pnl_refresher, :exit_manager, :active_cache, :reconciliation,
          :stats_notifier, :smc_scanner
        )
      end
    end

    it 'registers each ChainWatchService instance in Options::ChainWatchRegistry' do
      described_class.build_supervisor

      expect(Options::ChainWatchRegistry.snapshot_for('NIFTY')).not_to be_nil
      expect(Options::ChainWatchRegistry.snapshot_for('BANKNIFTY')).not_to be_nil
      expect(Options::ChainWatchRegistry.snapshot_for('SENSEX')).not_to be_nil
    ensure
      Options::ChainWatchRegistry.reset!
    end

    context 'when one index is disabled/unknown and ChainWatchService.new raises for it' do
      it 'does not register that index in the registry either' do
        original_new = Options::ChainWatchService.method(:new)
        allow(Options::ChainWatchService).to receive(:new) do |index_key:|
          raise "unknown_index:#{index_key}" if index_key == 'BANKNIFTY'

          original_new.call(index_key: index_key)
        end

        described_class.build_supervisor

        expect(Options::ChainWatchRegistry.snapshot_for('NIFTY')).not_to be_nil
        expect(Options::ChainWatchRegistry.snapshot_for('BANKNIFTY')).to be_nil
      ensure
        Options::ChainWatchRegistry.reset!
      end
    end
  end
end
