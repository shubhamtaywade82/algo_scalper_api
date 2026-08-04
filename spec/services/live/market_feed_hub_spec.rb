# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/VerifiedDoubles, RSpec/IdenticalEqualityAssertion, RSpec/MessageSpies
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

    # Clear TickCache
    TickCache.instance.clear

    # Ensure credentials are set (for enabled? check)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('CLIENT_ID').and_return('test_client_id')
    allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return('test_access_token')
    allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
    allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
    allow(ENV).to receive(:[]).with('BACKTEST_MODE').and_return(nil)
    allow(ENV).to receive(:[]).with('SCRIPT_MODE').and_return(nil)
    allow(ENV).to receive(:[]).with('DISABLE_TRADING_SERVICES').and_return(nil)
    allow(ENV).to receive(:[]).and_call_original

    # Mock DhanHQ::WS::Client via build_client to be 100% sure we capture the calls
    allow(hub).to receive(:build_client).and_return(ws_client)
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
    allow(hub).to receive_messages(load_watchlist: [], enabled?: true)
  end

  after do
    hub.stop!
  end

  describe 'EPIC B — B2: Auto-Subscribe on Boot' do
    describe '#start! - Boot Initialization' do
      context 'when enabled and credentials are present' do
        it 'returns true and marks hub as running' do
          expect(hub.start!).to be(true)
          expect(hub).to be_running
        end

        it 'creates WebSocket client with correct mode' do
          hub.start!
          expect(DhanHQ::WS::Client).to have_received(:new).with(mode: :quote)
        end

        it 'registers tick handler with WebSocket client' do
          hub.start!
          expect(ws_client_double).to have_received(:on).with(:tick)
        end

        it 'starts WebSocket client connection' do
          hub.start!
          expect(ws_client_double).to have_received(:start)
        end

        it 'logs successful start' do
          allow(Rails.logger).to receive(:info)
          hub.start!
          expect(Rails.logger).to have_received(:info).with(
            match(/DhanHQ market feed started/)
          )
        end
      end

      context 'when credentials are missing' do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
          allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return(nil)
          allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
          allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
        end

        it 'returns false and does not start' do
          result = hub.start!
          expect(result).to be_falsy
          expect(hub).not_to be_running
        end

        it 'does not create WebSocket client' do
          hub.start!
          expect(DhanHQ::WS::Client).not_to have_received(:new)
        end
      end

      context 'when already running' do
        before { hub.start! }

        it 'does not start again' do
          hub.start!
          # Should not create a new client (already started in before block)
          expect(DhanHQ::WS::Client).to have_received(:new).once
        end

        it 'remains running' do
          hub.start!
          expect(hub).to be_running
        end
      end

      context 'when start fails' do
        before do
          allow(ws_client_double).to receive(:start).and_raise(StandardError, 'Connection failed')
          allow(Rails.logger).to receive(:error)
        end

        it 'returns false' do
          expect(hub.start!).to be(false)
        end

        it 'does not mark as running' do
          hub.start!
          expect(hub).not_to be_running
        end

        it 'logs error' do
          hub.start!
          expect(Rails.logger).to have_received(:error).with(
            match(/Failed to start DhanHQ market feed/)
          )
        end

        it 'calls stop! to clean up' do
          expect(hub).to receive(:stop!).and_call_original
          hub.start!
        end
      end
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
  end

  describe 'operator disable flag' do
    it 'reports disabled when DISABLE_TRADING_SERVICES=1' do
      allow(hub).to receive(:enabled?).and_call_original
      allow(ENV).to receive(:[]).with('DISABLE_TRADING_SERVICES').and_return('1')

      expect(hub.send(:enabled?)).to be false
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles, RSpec/IdenticalEqualityAssertion, RSpec/MessageSpies
