# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  let(:hub) { described_class.instance }

  before do
    allow(Rails.application.config.x).to receive(:dhanhq).and_return(
      ActiveSupport::InheritableOptions.new(enabled: true, ws_enabled: true, ws_mode: :quote)
    )

    # Create a fresh mock for each test to avoid leakage
    @ws_double = instance_double(DhanHQ::WS::Client,
                                 start: true,
                                 on: true,
                                 subscribe_one: true,
                                 unsubscribe_one: true,
                                 disconnect!: true)

    allow(DhanHQ::WS::Client).to receive(:new).and_return(@ws_double)

    # Clean up only the specific WatchlistItem records created in this test file
    WatchlistItem.where(segment: %w[IDX_I NSE_FNO], security_id: %w[13 12345]).delete_all

    # Properly reset the singleton instance state
    hub.stop! if hub.running?
    hub.instance_variable_set(:@ws_client, nil)
    hub.instance_variable_set(:@running, false)
    hub.instance_variable_set(:@watchlist, nil)
    hub.instance_variable_set(:@callbacks, [])
  end

  after do
    # Clean up after each test
    hub.stop! if hub.running?
    hub.instance_variable_set(:@ws_client, nil)
    hub.instance_variable_set(:@running, false)
    hub.instance_variable_set(:@watchlist, nil)
  end

  describe '#start!' do
    it 'connects, registers tick handler, subscribes watchlist, and marks running' do
      WatchlistItem.create!(segment: 'IDX_I', security_id: '13')
      WatchlistItem.create!(segment: 'NSE_FNO', security_id: '12345')

      expect(@ws_double).to receive(:on).with(:tick)
      expect(@ws_double).to receive(:start)
      expect(@ws_double).to receive(:subscribe_many).with(
        req: :quote,
        list: [
          { segment: 'IDX_I', security_id: '13' },
          { segment: 'NSE_FNO', security_id: '12345' }
        ]
      )

      expect(hub.start!).to be(true)
      expect(hub).to be_running
    end
  end

  describe '#subscribe and #unsubscribe' do
    before { hub.start! }

    it 'subscribes one instrument' do
      expect(@ws_double).to receive(:subscribe_one).with(segment: 'NSE_FNO', security_id: '49081')
      hub.subscribe(segment: 'NSE_FNO', security_id: 49_081)
    end

    it 'unsubscribes one instrument' do
      expect(@ws_double).to receive(:unsubscribe_one).with(segment: 'NSE_FNO', security_id: '49081')
      hub.unsubscribe(segment: 'NSE_FNO', security_id: 49_081)
    end
  end

  describe 'tick handling and TickCache' do
    it 'writes ticks to Live::TickCache and exposes ltp' do
      # Clear any existing ticks to ensure clean state
      TickCache.instance.clear

      # Create a test tick
      tick = { segment: 'NSE_FNO', security_id: '49081', ltp: 123.45, kind: :quote }

      # Directly test the tick handling by calling the method
      hub.send(:handle_tick, tick)

      # Verify the tick was stored correctly
      expect(Live::TickCache.ltp('NSE_FNO', '49081')).to eq(123.45)
      expect(Live::TickCache.get('NSE_FNO', '49081')).to include(kind: :quote)
    end
  end

  describe '#stop!' do
    it 'disconnects the websocket client and clears running flag' do
      hub.start!
      expect(@ws_double).to receive(:disconnect!)
      hub.stop!
      expect(hub).not_to be_running
    end
  end
end
