# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  let(:hub) { described_class.instance }
  let(:ws_double) do
    instance_double('DhanHQ::WS::Client', start: true, on: true, subscribe_one: true, unsubscribe_one: true, disconnect!: true)
  end

  before do
    allow(Rails.application.config.x).to receive(:dhanhq).and_return(
      ActiveSupport::InheritableOptions.new(enabled: true, ws_enabled: true, ws_mode: :quote)
    )

    allow(DhanHQ::WS::Client).to receive(:new).and_return(ws_double)
    ::TickCache.instance.clear
  end

  describe '#start!' do
    it 'connects, registers tick handler, subscribes watchlist, and marks running' do
      WatchlistItem.create!(segment: 'IDX_I', security_id: '13')
      WatchlistItem.create!(segment: 'NSE_FNO', security_id: '12345')

      expect(ws_double).to receive(:on).with(:tick)
      expect(ws_double).to receive(:start)
      expect(ws_double).to receive(:subscribe_one).with(segment: 'IDX_I', security_id: '13')
      expect(ws_double).to receive(:subscribe_one).with(segment: 'NSE_FNO', security_id: '12345')

      expect(hub.start!).to eq(true)
      expect(hub).to be_running
    end
  end

  describe '#subscribe and #unsubscribe' do
    before { hub.start! }

    it 'subscribes one instrument' do
      expect(ws_double).to receive(:subscribe_one).with(segment: 'NSE_FNO', security_id: '49081')
      hub.subscribe(segment: 'NSE_FNO', security_id: 49081)
    end

    it 'unsubscribes one instrument' do
      expect(ws_double).to receive(:unsubscribe_one).with(segment: 'NSE_FNO', security_id: '49081')
      hub.unsubscribe(segment: 'NSE_FNO', security_id: 49081)
    end
  end

  describe 'tick handling and TickCache' do
    it 'writes ticks to Live::TickCache and exposes ltp' do
      hub.start!

      # Capture the on(:tick) block and invoke it with a sample tick
      called = nil
      allow(ws_double).to receive(:on) do |_, &blk|
        called = blk
      end

      # Restart to re-register on with our spy
      hub.stop!
      hub.start!

      tick = { segment: 'NSE_FNO', security_id: '49081', ltp: 123.45, kind: :quote }
      expect { called.call(tick) }.not_to raise_error

      expect(Live::TickCache.ltp('NSE_FNO', '49081')).to eq(123.45)
      expect(Live::TickCache.get('NSE_FNO', '49081')).to include(kind: :quote)
    end
  end

  describe '#stop!' do
    it 'disconnects the websocket client and clears running flag' do
      hub.start!
      expect(ws_double).to receive(:disconnect!)
      hub.stop!
      expect(hub).not_to be_running
    end
  end
end


