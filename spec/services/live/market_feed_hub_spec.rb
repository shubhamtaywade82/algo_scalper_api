# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  let(:hub) { described_class.instance }
  let(:ws_client) { double('DhanHQ::WS::Client') }

  before do
    # Force reset singleton state
    hub.instance_variable_set(:@running, false)
    hub.instance_variable_set(:@ws_client, nil)
    hub.instance_variable_set(:@connection_state, :disconnected)
    hub.instance_variable_set(:@subscribed_keys, Concurrent::Set.new)
    hub.instance_variable_set(:@watchlist_keys, Concurrent::Set.new)
    hub.instance_variable_set(:@callbacks, Concurrent::Array.new)
    hub.instance_variable_set(:@last_tick_at, nil)
    hub.instance_variable_set(:@watchdog_thread, nil)
    hub.instance_variable_set(:@restarting, false)

    # Mock environment
    allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return('test_client_id')
    allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return('test_access_token')
    allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
    allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
    allow(ENV).to receive(:[]).with('DISABLE_TRADING_SERVICES').and_return(nil)
    allow(ENV).to receive(:[]).with('BACKTEST_MODE').and_return(nil)
    allow(ENV).to receive(:[]).with('SCRIPT_MODE').and_return(nil)
    allow(ENV).to receive(:[]).and_call_original

    # Mock DhanHQ::WS::Client via build_client to be 100% sure we capture the calls
    allow(ws_client).to receive(:on).at_least(:once)
    allow(ws_client).to receive(:start)
    allow(ws_client).to receive(:disconnect!)
    allow(ws_client).to receive(:subscribe_one)
    allow(ws_client).to receive(:subscribe_many)
    allow(ws_client).to receive(:unsubscribe_one)
    allow(ws_client).to receive(:unsubscribe_many)
    allow(ws_client).to receive(:respond_to?).with(:disconnect!).and_return(true)
    allow(ws_client).to receive(:respond_to?).with(:connected?).and_return(false)

    # Prevent actual background threads or DB calls in unit tests
    allow(hub).to receive(:start_watchdog!)
    allow(hub).to receive(:subscribe_watchlist)
    allow(hub).to receive_messages(build_client: ws_client, load_watchlist: [], enabled?: true)
  end

  after do
    hub.stop!
  end

  describe 'singleton' do
    it 'returns the same instance' do
      expect(described_class.instance).to eq(described_class.instance)
    end
  end

  describe '#start!' do
    context 'when disabled' do
      before do
        allow(hub).to receive(:enabled?).and_return(false)
      end

      it 'returns false and does not start' do
        expect(hub.start!).to be false
        expect(hub.running?).to be false
        expect(ws_client).not_to have_received(:start)
      end
    end

    context 'when enabled and not running' do
      it 'starts the WebSocket client and sets running to true' do
        result = hub.start!

        expect(result).to be true
        expect(hub.running?).to be true
        expect(ws_client).to have_received(:start)
      end
    end

    context 'when already running' do
      it 'returns true without restarting' do
        hub.start!
        # Reset count for start check
        expect(ws_client).to have_received(:start).once

        expect(hub.start!).to be true
        # Should still be once
        expect(ws_client).to have_received(:start).once
      end
    end
  end

  describe '#stop!' do
    it 'stops the client and resets state' do
      hub.start!
      hub.stop!

      expect(hub.running?).to be false
      expect(hub.instance_variable_get(:@ws_client)).to be_nil
      expect(hub.instance_variable_get(:@subscribed_keys)).to be_empty
      expect(ws_client).to have_received(:disconnect!)
    end
  end

  describe '#subscribe' do
    before { hub.start! }

    it 'subscribes via WebSocket and tracks the key' do
      result = hub.subscribe(segment: 'NSE_FNO', security_id: '12345')

      expect(result[:already_subscribed]).to be false
      expect(hub.subscribed?(segment: 'NSE_FNO', security_id: '12345')).to be true
      expect(ws_client).to have_received(:subscribe_one).with(segment: 'NSE_FNO', security_id: '12345')
    end

    it 'skips if already subscribed' do
      hub.subscribe(segment: 'NSE_FNO', security_id: '12345')
      hub.subscribe(segment: 'NSE_FNO', security_id: '12345')

      expect(ws_client).to have_received(:subscribe_one).once
    end
  end

  describe '#handle_tick' do
    let(:tick) do
      {
        segment: 'NSE_FNO',
        security_id: '12345',
        ltp: 25_200.5,
        kind: :ticker,
        ts: Time.current.to_i
      }
    end

    before do
      hub.start!

      # Mock dependencies called in handle_tick
      allow(Live::TickCache).to receive(:put)
      allow(Live::FeedHealthService.instance).to receive(:mark_success!)
      allow(Live::SystemStatusCache.instance).to receive(:report_heartbeat)
      allow(Live::PositionIndex.instance).to receive(:trackers_for).and_return([])
    end

    it 'updates connection state to connected' do
      hub.send(:handle_tick, tick)
      expect(hub.instance_variable_get(:@connection_state)).to eq(:connected)
    end

    it 'triggers registered callbacks' do
      callback_called = false
      hub.on_tick { |_t| callback_called = true }
      hub.send(:handle_tick, tick)
      expect(callback_called).to be true
    end

    it 'updates TickCache' do
      hub.send(:handle_tick, tick)
      expect(Live::TickCache).to have_received(:put).with(tick)
    end
  end

  describe 'health check' do
    before do
      allow(Live::FeedHealthService.instance).to receive(:threshold_for).and_return(30)
      hub.start!
    end

    it 'restarts if ticks are stale' do
      hub.instance_variable_set(:@last_tick_at, 1.minute.ago)
      expect(hub).to receive(:restart!)
      hub.send(:check_connection_health!)
    end

    it 'does not restart if ticks are fresh' do
      hub.instance_variable_set(:@last_tick_at, 5.seconds.ago)
      expect(hub).not_to receive(:restart!)
      hub.send(:check_connection_health!)
    end
  end

  describe '#start! failure handling' do
    it 'returns false and does not report success when the WS client fails to start' do
      hub = described_class.instance
      broken_client = instance_double(DhanHQ::WS::Client)
      allow(hub).to receive_messages(enabled?: true, running?: false, load_watchlist: [], build_client: broken_client)
      allow(broken_client).to receive(:on)
      allow(broken_client).to receive(:start).and_raise('connection refused')
      allow(hub).to receive(:stop!)

      result = hub.start!

      expect(result).to be false
      expect(hub).to have_received(:stop!)
    end
  end

  describe '#healthy?' do
    it 'delegates to the WS client healthy? when available' do
      hub = described_class.instance
      allow(hub).to receive(:running?).and_return(true)
      client = instance_double(DhanHQ::WS::Client, healthy?: true)
      hub.instance_variable_set(:@ws_client, client)

      expect(hub.healthy?).to be true
      expect(client).to have_received(:healthy?).with(stale_after: 45)
    end

    it 'is false when not running' do
      hub = described_class.instance
      allow(hub).to receive(:running?).and_return(false)

      expect(hub.healthy?).to be false
    end
  end
end
