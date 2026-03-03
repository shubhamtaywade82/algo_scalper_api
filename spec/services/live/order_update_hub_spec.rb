# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::OrderUpdateHub do
  let(:hub) { described_class.instance }
  let(:ws_client) { instance_double(DhanHQ::WS::Orders::Client) }

  before do
    # Reset singleton state
    hub.instance_variable_set(:@running, false)
    hub.instance_variable_set(:@ws_client, nil)
    hub.instance_variable_set(:@callbacks, Concurrent::Array.new)

    # Stub AlgoConfig
    allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })

    # Stub environment variables
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return('test_client_id')
    allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return('test_access_token')
    allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
    allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)

    # Stub WebSocket client
    allow(DhanHQ::WS::Orders::Client).to receive(:new).and_return(ws_client)
    allow(ws_client).to receive(:on)
    allow(ws_client).to receive(:start)
    allow(ws_client).to receive(:stop)
  end

  describe '#initialize' do
    it 'initializes with empty callbacks array' do
      new_hub = described_class.instance
      expect(new_hub.instance_variable_get(:@callbacks)).to be_a(Concurrent::Array)
    end

    it 'initializes with mutex' do
      expect(hub.instance_variable_get(:@lock)).to be_a(Mutex)
    end
  end

  describe '#start!' do
    context 'when enabled' do
      it 'starts WebSocket client' do
        hub.start!

        expect(DhanHQ::WS::Orders::Client).to have_received(:new)
        expect(ws_client).to have_received(:start)
      end

      it 'registers update handler' do
        hub.start!

        expect(ws_client).to have_received(:on).with(:update)
      end

      it 'sets running to true' do
        hub.start!

        expect(hub.running?).to be true
      end

      it 'returns true on success' do
        result = hub.start!

        expect(result).to be true
      end

      it 'logs start message' do
        expect(Rails.logger).to receive(:info).with('[OrderUpdateHub] DhanHQ order update feed started (live mode only)')

        hub.start!
      end
    end

    context 'when already running' do
      it 'does not start again' do
        hub.start!
        hub.start!

        expect(ws_client).to have_received(:start).once
      end

      it 'returns true' do
        hub.start!
        result = hub.start!

        expect(result).to be true
      end
    end

    context 'when paper trading is enabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
      end

      it 'does not start WebSocket client' do
        hub.start!

        expect(DhanHQ::WS::Orders::Client).not_to have_received(:new)
        expect(ws_client).not_to have_received(:start)
      end

      it 'returns false' do
        result = hub.start!

        expect(result).to be false
      end

      it 'does not set running to true' do
        hub.start!

        expect(hub.running?).to be false
      end
    end

    context 'when credentials are missing' do
      before do
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return(nil)
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
      end

      it 'does not start WebSocket client' do
        hub.start!

        expect(DhanHQ::WS::Orders::Client).not_to have_received(:new)
      end

      it 'returns false' do
        result = hub.start!

        expect(result).to be false
      end
    end

    context 'when WebSocket client raises error' do
      before do
        allow(ws_client).to receive(:start).and_raise(StandardError.new('Connection failed'))
      end

      it 'handles error gracefully' do
        expect { hub.start! }.not_to raise_error
      end

      it 'calls stop!' do
        expect(hub).to receive(:stop!)

        hub.start!
      end

      it 'returns false' do
        result = hub.start!

        expect(result).to be false
      end

      it 'logs error' do
        expect(Rails.logger).to receive(:error).with(/OrderUpdateHub.*Failed to start/)

        hub.start!
      end
    end

    context 'with alternative credential names' do
      before do
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return(nil)
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return('alt_client_id')
        allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return('alt_access_token')
      end

      it 'uses alternative credential names' do
        hub.start!

        expect(hub.running?).to be true
      end
    end
  end

  describe '#stop!' do
    before do
      hub.instance_variable_set(:@ws_client, ws_client)
      hub.instance_variable_set(:@running, true)
    end

    it 'stops WebSocket client' do
      hub.stop!

      expect(ws_client).to have_received(:stop)
    end

    it 'sets running to false' do
      hub.stop!

      expect(hub.running?).to be false
    end

    it 'clears ws_client' do
      hub.stop!

      expect(hub.instance_variable_get(:@ws_client)).to be_nil
    end

    it 'handles stop errors gracefully' do
      allow(ws_client).to receive(:stop).and_raise(StandardError.new('Stop failed'))

      expect { hub.stop! }.not_to raise_error
      expect(hub.running?).to be false
    end

    it 'logs warning on stop error' do
      allow(ws_client).to receive(:stop).and_raise(StandardError.new('Stop failed'))

      expect(Rails.logger).to receive(:warn).with(/OrderUpdateHub.*Error while stopping/)

      hub.stop!
    end

    context 'when ws_client is nil' do
      before do
        hub.instance_variable_set(:@ws_client, nil)
      end

      it 'does not raise error' do
        expect { hub.stop! }.not_to raise_error
      end

      it 'sets running to false' do
        hub.stop!

        expect(hub.running?).to be false
      end
    end
  end

  describe '#running?' do
    it 'returns false initially' do
      expect(hub.running?).to be false
    end

    it 'returns true after start' do
      hub.start!

      expect(hub.running?).to be true
    end

    it 'returns false after stop' do
      hub.start!
      hub.stop!

      expect(hub.running?).to be false
    end
  end

  describe '#on_update' do
    it 'registers callback' do
      callback = proc { |payload| puts payload }

      hub.on_update(&callback)

      callbacks = hub.instance_variable_get(:@callbacks)
      expect(callbacks).to include(callback)
    end

    it 'raises error if no block provided' do
      expect { hub.on_update }.to raise_error(ArgumentError, 'block required')
    end

    it 'allows multiple callbacks' do
      callback1 = proc { |p| puts "1: #{p}" }
      callback2 = proc { |p| puts "2: #{p}" }

      hub.on_update(&callback1)
      hub.on_update(&callback2)

      callbacks = hub.instance_variable_get(:@callbacks)
      expect(callbacks.size).to eq(2)
    end
  end

  describe '#handle_update' do
    let(:payload) { { orderNo: 'TEST123', orderStatus: 'TRADED', averagePrice: 100.5 } }

    before do
      hub.start!
    end

    it 'normalizes payload keys' do
      expect(ActiveSupport::Notifications).to receive(:instrument) do |event, normalized|
        expect(event).to eq('dhanhq.order_update')
        expect(normalized).to have_key(:order_no)
        expect(normalized).to have_key(:order_status)
        expect(normalized).to have_key(:average_price)
      end

      hub.send(:handle_update, payload)
    end

    it 'publishes notification' do
      expect(ActiveSupport::Notifications).to receive(:instrument).with('dhanhq.order_update', anything)

      hub.send(:handle_update, payload)
    end

    it 'invokes registered callbacks' do
      callback_called = false
      callback_payload = nil

      hub.on_update do |payload|
        callback_called = true
        callback_payload = payload
      end

      hub.send(:handle_update, payload)

      expect(callback_called).to be true
      expect(callback_payload).to have_key(:order_no)
    end

    it 'handles callback errors gracefully' do
      hub.on_update { |_p| raise StandardError, 'Callback error' }

      expect { hub.send(:handle_update, payload) }.not_to raise_error
    end

    it 'logs callback errors' do
      hub.on_update { |_p| raise StandardError, 'Callback error' }

      expect(Rails.logger).to receive(:error).with(/OrderUpdateHub.*Order update callback failed/)

      hub.send(:handle_update, payload)
    end
  end

  describe '#normalize' do
    it 'converts camelCase keys to snake_case symbols' do
      payload = { orderNo: '123', orderStatus: 'TRADED', averagePrice: 100.5 }

      normalized = hub.send(:normalize, payload)

      expect(normalized).to eq(
        order_no: '123',
        order_status: 'TRADED',
        average_price: 100.5
      )
    end

    it 'handles nested hashes' do
      payload = { order: { orderNo: '123', status: 'TRADED' } }

      normalized = hub.send(:normalize, payload)

      expect(normalized[:order]).to have_key(:order_no)
    end

    it 'returns payload as-is if not a hash' do
      payload = 'not a hash'

      normalized = hub.send(:normalize, payload)

      expect(normalized).to eq('not a hash')
    end
  end

  describe '#paper_trading_enabled?' do
    it 'returns true when paper trading is enabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })

      expect(hub.send(:paper_trading_enabled?)).to be true
    end

    it 'returns false when paper trading is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })

      expect(hub.send(:paper_trading_enabled?)).to be false
    end

    it 'returns false when AlgoConfig.fetch raises error' do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError.new('Config error'))

      expect(hub.send(:paper_trading_enabled?)).to be false
    end

    it 'returns false when paper_trading key is missing' do
      allow(AlgoConfig).to receive(:fetch).and_return({})

      expect(hub.send(:paper_trading_enabled?)).to be false
    end
  end
end
