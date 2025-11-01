# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub, :vcr do
  let(:hub) { described_class.instance }

  let(:ws_client_double) do
    instance_double(DhanHQ::WS::Client,
                    start: true,
                    on: true,
                    subscribe_one: true,
                    unsubscribe_one: true,
                    subscribe_many: true,
                    unsubscribe_many: true,
                    disconnect!: true)
  end

  before do
    # Mock Rails config
    allow(Rails.application.config.x).to receive(:dhanhq).and_return(
      ActiveSupport::InheritableOptions.new(enabled: true, ws_enabled: true, ws_mode: :quote)
    )

    # Mock DhanHQ::WS::Client
    allow(DhanHQ::WS::Client).to receive(:new).and_return(ws_client_double)

    # Clean up watchlist items
    WatchlistItem.where(segment: %w[IDX_I NSE_FNO], security_id: %w[13 25 51 12345]).delete_all

    # Reset singleton instance state
    hub.stop! if hub.running?
    hub.instance_variable_set(:@ws_client, nil)
    hub.instance_variable_set(:@running, false)
    hub.instance_variable_set(:@watchlist, nil)
    hub.instance_variable_set(:@callbacks, Concurrent::Array.new)

    # Clear TickCache
    TickCache.instance.clear

    # Ensure credentials are set (for enabled? check)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('DHANHQ_CLIENT_ID').and_return('test_client_id')
    allow(ENV).to receive(:[]).with('DHANHQ_ACCESS_TOKEN').and_return('test_access_token')
    allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
    allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
  end

  after do
    # Clean up after each test
    hub.stop! if hub.running?
    hub.instance_variable_set(:@ws_client, nil)
    hub.instance_variable_set(:@running, false)
    hub.instance_variable_set(:@watchlist, nil)
    WatchlistItem.where(segment: %w[IDX_I NSE_FNO], security_id: %w[13 25 51 12345]).delete_all
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
          allow(ENV).to receive(:[]).with('DHANHQ_CLIENT_ID').and_return(nil)
          allow(ENV).to receive(:[]).with('DHANHQ_ACCESS_TOKEN').and_return(nil)
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

    describe 'Watchlist Subscription on Start' do
      context 'with active WatchlistItems in database' do
        let!(:nifty) do
          create(:watchlist_item, segment: 'IDX_I', security_id: '13', active: true)
        end
        let!(:banknifty) do
          create(:watchlist_item, segment: 'IDX_I', security_id: '25', active: true)
        end
        let!(:inactive_item) do
          create(:watchlist_item, segment: 'IDX_I', security_id: '51', active: false)
        end

        it 'loads only active watchlist items' do
          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist).to contain_exactly(
            { segment: 'IDX_I', security_id: '13' },
            { segment: 'IDX_I', security_id: '25' }
          )
        end

        it 'excludes inactive watchlist items' do
          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist).not_to include(
            hash_including(segment: 'IDX_I', security_id: '51')
          )
        end

        it 'subscribes to all active watchlist items via subscribe_many' do
          hub.start!
          expect(ws_client_double).to have_received(:subscribe_many).with(
            req: :quote,
            list: [
              { segment: 'IDX_I', security_id: '13' },
              { segment: 'IDX_I', security_id: '25' }
            ]
          )
        end

        it 'orders watchlist items by segment and security_id' do
          # Create items in different order
          create(:watchlist_item, segment: 'NSE_FNO', security_id: '999', active: true)
          create(:watchlist_item, segment: 'IDX_I', security_id: '10', active: true)

          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist.first[:segment]).to eq('IDX_I')
          expect(watchlist.first[:security_id]).to eq('10')
        end

        it 'logs subscription count' do
          allow(Rails.logger).to receive(:info)
          hub.start!
          expect(Rails.logger).to have_received(:info).with(
            '[MarketFeedHub] Subscribed to 2 instruments using subscribe_many'
          )
        end
      end

      context 'when watchlist is empty' do
        it 'does not call subscribe_many' do
          hub.start!
          expect(ws_client_double).not_to have_received(:subscribe_many)
        end

        it 'sets watchlist to empty array' do
          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist).to eq([])
        end
      end

      context 'with ENV fallback when DB watchlist is empty' do
        before do
          WatchlistItem.delete_all
          allow(ENV).to receive(:fetch).with('DHANHQ_WS_WATCHLIST', '').and_return(
            'IDX_I:13,IDX_I:25;NSE_FNO:12345'
          )
        end

        it 'loads watchlist from ENV variable' do
          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist).to contain_exactly(
            { segment: 'IDX_I', security_id: '13' },
            { segment: 'IDX_I', security_id: '25' },
            { segment: 'NSE_FNO', security_id: '12345' }
          )
        end

        it 'subscribes to ENV watchlist items' do
          hub.start!
          expect(ws_client_double).to have_received(:subscribe_many).with(
            req: :quote,
            list: array_including(
              { segment: 'IDX_I', security_id: '13' },
              { segment: 'NSE_FNO', security_id: '12345' }
            )
          )
        end

        it 'handles various ENV separators (comma, semicolon, newline)' do
          allow(ENV).to receive(:fetch).with('DHANHQ_WS_WATCHLIST', '').and_return(
            "IDX_I:13\nIDX_I:25,NSE_FNO:12345"
          )
          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist.size).to eq(3)
        end

        it 'filters out blank entries' do
          allow(ENV).to receive(:fetch).with('DHANHQ_WS_WATCHLIST', '').and_return(
            'IDX_I:13,,IDX_I:25;'
          )
          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist.size).to eq(2)
        end
      end

      context 'when DB watchlist exists, ENV is ignored' do
        let!(:db_item) do
          create(:watchlist_item, segment: 'IDX_I', security_id: '13', active: true)
        end

        before do
          allow(ENV).to receive(:fetch).with('DHANHQ_WS_WATCHLIST', '').and_return(
            'NSE_FNO:999'
          )
        end

        it 'prefers DB watchlist over ENV' do
          hub.start!
          watchlist = hub.instance_variable_get(:@watchlist)
          expect(watchlist).to contain_exactly(
            { segment: 'IDX_I', security_id: '13' }
          )
          expect(watchlist).not_to include(
            hash_including(segment: 'NSE_FNO', security_id: '999')
          )
        end
      end
    end

    describe 'Tick Storage' do
      let!(:watchlist_item) do
        create(:watchlist_item, segment: 'NSE_FNO', security_id: '49081', active: true)
      end

      before do
        hub.start!
        TickCache.instance.clear
      end

      it 'stores ticks in Live::TickCache when handle_tick is called' do
        tick = {
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 123.45,
          kind: :quote,
          timestamp: Time.current.to_i
        }

        hub.send(:handle_tick, tick)

        expect(Live::TickCache.ltp('NSE_FNO', '49081')).to eq(123.45)
        cached_tick = Live::TickCache.get('NSE_FNO', '49081')
        expect(cached_tick).to include(
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 123.45,
          kind: :quote
        )
      end

      it 'updates existing tick data when new tick arrives' do
        # First tick
        tick1 = {
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 100.0,
          kind: :quote
        }
        hub.send(:handle_tick, tick1)
        expect(Live::TickCache.ltp('NSE_FNO', '49081')).to eq(100.0)

        # Second tick with new LTP
        tick2 = {
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 105.5,
          kind: :quote
        }
        hub.send(:handle_tick, tick2)
        expect(Live::TickCache.ltp('NSE_FNO', '49081')).to eq(105.5)
      end

      it 'handles multiple segments and security_ids' do
        tick1 = { segment: 'IDX_I', security_id: '13', ltp: 20_000.0, kind: :quote }
        tick2 = { segment: 'NSE_FNO', security_id: '49081', ltp: 123.45, kind: :quote }

        hub.send(:handle_tick, tick1)
        hub.send(:handle_tick, tick2)

        expect(Live::TickCache.ltp('IDX_I', '13')).to eq(20_000.0)
        expect(Live::TickCache.ltp('NSE_FNO', '49081')).to eq(123.45)
      end

      it 'fires ActiveSupport::Notifications event for each tick' do
        tick = {
          segment: 'NSE_FNO',
          security_id: '49081',
          ltp: 123.45,
          kind: :quote
        }

        expect(ActiveSupport::Notifications).to receive(:instrument).with(
          'dhanhq.tick',
          tick
        )

        hub.send(:handle_tick, tick)
      end
    end

    describe 'Manual Subscription/Unsubscription' do
      before { hub.start! }

      describe '#subscribe' do
        it 'subscribes to a single instrument' do
          hub.subscribe(segment: 'NSE_FNO', security_id: 49_081)
          expect(ws_client_double).to have_received(:subscribe_one).with(
            segment: 'NSE_FNO',
            security_id: '49081'
          )
        end

        it 'converts security_id to string' do
          hub.subscribe(segment: 'IDX_I', security_id: 13)
          expect(ws_client_double).to have_received(:subscribe_one).with(
            segment: 'IDX_I',
            security_id: '13'
          )
        end

        it 'returns subscription params' do
          result = hub.subscribe(segment: 'NSE_FNO', security_id: 49_081)
          expect(result).to eq({ segment: 'NSE_FNO', security_id: '49081' })
        end

        it 'auto-starts hub if not running' do
          hub.stop!
          allow(ws_client_double).to receive(:start).and_return(true)
          expect(hub).to receive(:start!).and_call_original
          hub.subscribe(segment: 'NSE_FNO', security_id: 49_081)
        end
      end

      describe '#subscribe_many' do
        let(:instruments) do
          [
            { segment: 'IDX_I', security_id: '13' },
            { segment: 'NSE_FNO', security_id: '12345' }
          ]
        end

        it 'subscribes to multiple instruments' do
          hub.subscribe_many(instruments)
          expect(ws_client_double).to have_received(:subscribe_many).with(
            req: :quote,
            list: [
              { segment: 'IDX_I', security_id: '13' },
              { segment: 'NSE_FNO', security_id: '12345' }
            ]
          )
        end

        it 'handles empty array' do
          hub.subscribe_many([])
          expect(ws_client_double).not_to have_received(:subscribe_many)
        end

        it 'handles ActiveRecord models' do
          instrument = instance_double(
            Instrument,
            segment: 'IDX_I',
            security_id: '13'
          )
          hub.subscribe_many([instrument])
          expect(ws_client_double).to have_received(:subscribe_many).with(
            req: :quote,
            list: [{ segment: 'IDX_I', security_id: '13' }]
          )
        end

        it 'logs batch subscription count' do
          allow(Rails.logger).to receive(:info)
          hub.subscribe_many(instruments)
          expect(Rails.logger).to have_received(:info).with(
            '[MarketFeedHub] Batch subscribed to 2 instruments'
          )
        end
      end

      describe '#unsubscribe' do
        it 'unsubscribes from a single instrument' do
          hub.unsubscribe(segment: 'NSE_FNO', security_id: 49_081)
          expect(ws_client_double).to have_received(:unsubscribe_one).with(
            segment: 'NSE_FNO',
            security_id: '49081'
          )
        end

        it 'returns nil if hub is not running' do
          hub.stop!
          result = hub.unsubscribe(segment: 'NSE_FNO', security_id: 49_081)
          expect(result).to be_nil
          expect(ws_client_double).not_to have_received(:unsubscribe_one)
        end
      end

      describe '#unsubscribe_many' do
        let(:instruments) do
          [
            { segment: 'IDX_I', security_id: '13' },
            { segment: 'NSE_FNO', security_id: '12345' }
          ]
        end

        it 'unsubscribes from multiple instruments' do
          hub.unsubscribe_many(instruments)
          expect(ws_client_double).to have_received(:unsubscribe_many).with(
            req: :quote,
            list: [
              { segment: 'IDX_I', security_id: '13' },
              { segment: 'NSE_FNO', security_id: '12345' }
            ]
          )
        end

        it 'returns empty array if hub is not running' do
          hub.stop!
          result = hub.unsubscribe_many(instruments)
          expect(result).to eq([])
          expect(ws_client_double).not_to have_received(:unsubscribe_many)
        end

        it 'returns empty array for empty input' do
          result = hub.unsubscribe_many([])
          expect(result).to eq([])
          expect(ws_client_double).not_to have_received(:unsubscribe_many)
        end
      end
    end

    describe '#stop!' do
      before { hub.start! }

      it 'disconnects the WebSocket client' do
        hub.stop!
        expect(ws_client_double).to have_received(:disconnect!)
      end

      it 'clears running flag' do
        hub.stop!
        expect(hub).not_to be_running
      end

      it 'clears WebSocket client reference' do
        hub.stop!
        expect(hub.instance_variable_get(:@ws_client)).to be_nil
      end

      it 'handles disconnect errors gracefully' do
        allow(ws_client_double).to receive(:disconnect!).and_raise(StandardError, 'Disconnect failed')
        allow(Rails.logger).to receive(:warn)

        expect { hub.stop! }.not_to raise_error
        expect(Rails.logger).to have_received(:warn).with(
          match(/Error while stopping/)
        )
      end

      it 'ensures WebSocket client is cleared even on error' do
        allow(ws_client_double).to receive(:disconnect!).and_raise(StandardError)
        hub.stop!
        expect(hub.instance_variable_get(:@ws_client)).to be_nil
      end
    end

    describe 'Callback Registration' do
      describe '#on_tick' do
        it 'registers a callback' do
          callback = proc { |_tick| }
          hub.on_tick(&callback)
          callbacks = hub.instance_variable_get(:@callbacks)
          expect(callbacks).to include(callback)
        end

        it 'requires a block' do
          expect { hub.on_tick }.to raise_error(ArgumentError, 'block required')
        end

        it 'invokes registered callbacks when tick is received' do
          callback1_called = false
          callback2_called = false

          callback1 = proc { |_tick| callback1_called = true }
          callback2 = proc { |_tick| callback2_called = true }

          hub.on_tick(&callback1)
          hub.on_tick(&callback2)

          tick = { segment: 'NSE_FNO', security_id: '49081', ltp: 123.45, kind: :quote }
          hub.send(:handle_tick, tick)

          expect(callback1_called).to be(true)
          expect(callback2_called).to be(true)
        end

        it 'handles callback errors gracefully' do
          error_callback = proc { |_tick| raise StandardError, 'Callback error' }
          normal_callback = proc { |_tick| }

          hub.on_tick(&error_callback)
          hub.on_tick(&normal_callback)

          allow(Rails.logger).to receive(:error)
          tick = { segment: 'NSE_FNO', security_id: '49081', ltp: 123.45, kind: :quote }

          expect { hub.send(:handle_tick, tick) }.not_to raise_error
          expect(Rails.logger).to have_received(:error).with(
            match(/DhanHQ tick callback failed/)
          )
        end
      end
    end

    describe 'Reconnection Behavior' do
      # NOTE: Reconnection is handled by DhanHQ::WS::Client library
      # We verify that the client is properly initialized and configured
      # Actual reconnection testing would require integration tests with real WebSocket

      it 'configures client for automatic reconnection' do
        # The DhanHQ::WS::Client library handles reconnection internally
        # We verify that the client is created with correct mode
        hub.start!
        expect(DhanHQ::WS::Client).to have_received(:new).with(mode: :quote)
      end

      it 'maintains watchlist for re-subscription' do
        create(:watchlist_item, segment: 'IDX_I', security_id: '13', active: true)
        hub.start!
        watchlist = hub.instance_variable_get(:@watchlist)
        expect(watchlist).to be_present
        # The DhanHQ client library maintains subscription state internally
      end
    end
  end

  describe 'Edge Cases and Error Handling' do
    it 'handles invalid watchlist entries gracefully' do
      allow(ENV).to receive(:fetch).with('DHANHQ_WS_WATCHLIST', '').and_return(
        'invalid_entry,IDX_I:13,no_colon'
      )
      hub.start!
      watchlist = hub.instance_variable_get(:@watchlist)
      expect(watchlist).to contain_exactly(
        { segment: 'IDX_I', security_id: '13' }
      )
    end

    it 'handles watchlist items with blank security_id' do
      allow(ENV).to receive(:fetch).with('DHANHQ_WS_WATCHLIST', '').and_return(
        'IDX_I:,IDX_I:13'
      )
      hub.start!
      watchlist = hub.instance_variable_get(:@watchlist)
      expect(watchlist).to contain_exactly(
        { segment: 'IDX_I', security_id: '13' }
      )
    end
  end
end
