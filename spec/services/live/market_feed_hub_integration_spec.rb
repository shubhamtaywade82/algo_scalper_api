# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Live::MarketFeedHub Integration" do
  let(:hub) { Live::MarketFeedHub.instance }
  let(:ws_client) { double('DhanHQ::WS::Client') }
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: :nse, segment: :index) }
  let!(:tracker) { create(:position_tracker, :active, instrument: instrument, security_id: '12345', symbol: 'NIFTY24MAR22000CE', segment: 'NSE_FNO') }

  let(:tick) do
    {
      segment: 'NSE_FNO',
      security_id: '12345',
      ltp: 155.5,
      symbol: 'NIFTY24MAR22000CE',
      instrument_type: 'OPTIDX',
      oi: 10_000,
      volume: 50_000,
      kind: :ticker
    }
  end

  before do
    # Use MemoryStore for caching
    memory_store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(memory_store)

    # Mock Market status
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)

    # Reset singleton state
    hub.instance_variable_set(:@running, false)
    hub.instance_variable_set(:@ws_client, nil)
    hub.instance_variable_set(:@connection_state, :disconnected)
    hub.instance_variable_set(:@subscribed_keys, Concurrent::Set.new)
    hub.instance_variable_set(:@callbacks, Concurrent::Array.new)

    # Mock environment/client
    allow(ws_client).to receive(:on)
    allow(ws_client).to receive(:start)
    allow(ws_client).to receive_messages(subscribe_one: { already_subscribed: false }, subscribe_many: [])
    allow(hub).to receive(:start_watchdog!)
    allow(hub).to receive_messages(build_client: ws_client, load_watchlist: [])

    # Enable hub
    hub.start!

    # Mock PositionIndex
    allow(Live::PositionIndex.instance).to receive(:trackers_for).and_return([])
    allow(Live::PositionIndex.instance).to receive(:trackers_for).with('12345').and_return([{ id: tracker.id, entry_price: 150.0, quantity: 50 }])

    # Mock PnlUpdaterService
    allow(Live::PnlUpdaterService.instance).to receive(:cache_intermediate_pnl)

    # Mock internal health/status services
    allow(Live::FeedHealthService.instance).to receive(:mark_success!)
    allow(Live::FeedHealthService.instance).to receive(:threshold_for).and_return(30)
    allow(Live::SystemStatusCache.instance).to receive(:report_heartbeat)

    # Mock current positions to avoid resubscribe logic failures
    allow(Positions::ActivePositionsCache.instance).to receive(:active_trackers).and_return([tracker])
  end

  after do
    hub.stop!
  end

  describe 'Tick processing Pipeline' do
    it 'updates all caches and triggers cascading services' do
      # 1. Trigger the tick
      hub.send(:handle_tick, tick)

      # 2. Verify TickCache (Central LTP store)
      expect(Live::TickCache.ltp('NSE_FNO', '12345')).to eq(155.5)

      # 3. Verify MarketCache (Institutional/Reporting data)
      expect(MarketData::MarketCache.ltp('NIFTY24MAR22000CE')).to eq(155.5)

      # 4. Verify PnlUpdaterService (Trading PnL path)
      expect(Live::PnlUpdaterService.instance).to have_received(:cache_intermediate_pnl).with(
        tracker_id: tracker.id,
        ltp: 155.5
      )
    end

    it 'correctly handles index ticks for institutional data' do
      index_tick = {
        segment: 'IDX_I',
        security_id: '13',
        ltp: 22_150.75,
        symbol: 'NIFTY',
        instrument_type: 'INDEX',
        kind: :ticker
      }

      hub.send(:handle_tick, index_tick)

      expect(MarketData::MarketCache.ltp('NIFTY', is_index: true)).to eq(22_150.75)
    end

    it 'notifies custom callbacks' do
      callback_received = false
      hub.on_tick { |t| callback_received = true if t[:security_id] == '12345' }

      hub.send(:handle_tick, tick)
      expect(callback_received).to be true
    end
  end
end
