# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentHelpers, type: :concern do
  include ActiveSupport::Testing::TimeHelpers

  let(:instrument) { create(:instrument, :nifty_future, security_id: '50074') }
  let(:derivative) { create(:derivative, :nifty_call_option, instrument: instrument, security_id: '60001') }
  let(:ws_hub) { Live::WsHub.instance }
  let(:redis_cache) { Live::RedisPnlCache.instance }

  before do
    allow(ws_hub).to receive(:running?).and_return(true)
    allow(ws_hub).to receive(:subscribe).and_return(true)
    allow(redis_cache).to receive(:fetch_tick).and_return(nil)
    allow(redis_cache).to receive(:clear_tick)
  end

  describe '#resolve_ltp' do
    it 'returns BigDecimal from meta ltp when provided' do
      result = instrument.resolve_ltp(
        segment: 'NSE_FNO',
        security_id: '12345',
        meta: { ltp: 201.25 }
      )
      expect(result).to eq(BigDecimal('201.25'))
    end

    it 'handles string ltp in meta' do
      result = instrument.resolve_ltp(
        segment: 'NSE_FNO',
        security_id: '12345',
        meta: { ltp: '199.55' }
      )
      expect(result).to eq(BigDecimal('199.55'))
    end

    it 'falls back to Redis tick cache when meta ltp missing' do
      allow(redis_cache).to receive(:fetch_tick).with(segment: 'NSE_FNO', security_id: '12345')
                                                .and_return({ ltp: 199.55 })

      result = instrument.resolve_ltp(segment: 'NSE_FNO', security_id: '12345')
      expect(result).to eq(BigDecimal('199.55'))
    end

    it 'returns nil when no sources available' do
      allow(redis_cache).to receive(:fetch_tick).and_return(nil)

      result = instrument.resolve_ltp(segment: 'NSE_FNO', security_id: '12345')
      expect(result).to be_nil
    end

    it 'handles Redis tick with string ltp' do
      allow(redis_cache).to receive(:fetch_tick).and_return({ ltp: '200.75' })

      result = instrument.resolve_ltp(segment: 'NSE_FNO', security_id: '12345')
      expect(result).to eq(BigDecimal('200.75'))
    end

    it 'handles errors gracefully' do
      allow(redis_cache).to receive(:fetch_tick).and_raise(StandardError, 'Redis error')
      allow(Rails.logger).to receive(:error)

      result = instrument.resolve_ltp(segment: 'NSE_FNO', security_id: '12345')
      expect(result).to be_nil
      expect(Rails.logger).to have_received(:error)
    end
  end

  describe '#default_client_order_id' do
    it 'builds a deterministic prefix with side and security_id' do
      travel_to Time.zone.parse('2025-01-15 10:30:00') do
        id = instrument.default_client_order_id(side: :buy, security_id: '12345')
        expect(id).to start_with('AS-BUY-12345-')
        expect(id.length).to be >= 15
      end
    end

    it 'handles sell side' do
      id = instrument.default_client_order_id(side: :sell, security_id: '67890')
      expect(id).to start_with('AS-SEL-67890-')
    end

    it 'handles string side' do
      id = instrument.default_client_order_id(side: 'buy', security_id: '12345')
      expect(id).to start_with('AS-BUY-12345-')
    end

    it 'includes timestamp suffix' do
      travel_to Time.zone.parse('2025-01-15 10:30:00') do
        id = instrument.default_client_order_id(side: :buy, security_id: '12345')
        expect(id).to match(/AS-BUY-12345-\d{6}/)
      end
    end
  end

  describe '#ensure_ws_subscription!' do
    it 'subscribes when websocket hub is running' do
      allow(ws_hub).to receive(:running?).and_return(true)
      allow(ws_hub).to receive(:subscribe).with(seg: 'NSE_FNO', sid: '12345').and_return(true)

      expect do
        instrument.ensure_ws_subscription!(segment: 'NSE_FNO', security_id: '12345')
      end.not_to raise_error

      expect(ws_hub).to have_received(:subscribe)
    end

    it 'raises error when websocket hub is offline' do
      allow(ws_hub).to receive(:running?).and_return(false)
      allow(Rails.logger).to receive(:error)

      expect do
        instrument.ensure_ws_subscription!(segment: 'NSE_FNO', security_id: '12345')
      end.to raise_error('WebSocket hub not running')

      expect(Rails.logger).to have_received(:error)
    end

    it 'converts security_id to string' do
      allow(ws_hub).to receive(:running?).and_return(true)
      allow(ws_hub).to receive(:subscribe).and_return(true)

      instrument.ensure_ws_subscription!(segment: 'NSE_FNO', security_id: 12345)
      expect(ws_hub).to have_received(:subscribe).with(seg: 'NSE_FNO', sid: '12345')
    end
  end

  describe '#after_order_track!' do
    let(:order_response) { double('Order', order_id: 'ORD123456') }

    before do
      allow(ws_hub).to receive(:running?).and_return(true)
      allow(ws_hub).to receive(:subscribe).and_return(true)
      allow(redis_cache).to receive(:clear_tick)
    end

    it 'creates an active position tracker' do
      expect do
        instrument.after_order_track!(
          instrument: instrument,
          order_no: 'ORD123456',
          segment: 'NSE_FNO',
          security_id: '12345',
          side: 'LONG',
          qty: 50,
          entry_price: BigDecimal('100.5'),
          symbol: 'NIFTY'
        )
      end.to change(PositionTracker, :count).by(1)

      tracker = PositionTracker.last
      expect(tracker.status).to eq(PositionTracker::STATUSES[:active])
      expect(tracker.side).to eq('LONG')
      expect(tracker.entry_price).to eq(BigDecimal('100.5'))
      expect(tracker.quantity).to eq(50)
      expect(tracker.order_no).to eq('ORD123456')
      expect(tracker.security_id).to eq('12345')
      expect(tracker.segment).to eq('NSE_FNO')
      expect(tracker.symbol).to eq('NIFTY')
    end

    it 'includes index_key in meta if provided' do
      instrument.after_order_track!(
        instrument: instrument,
        order_no: 'ORD123456',
        segment: 'NSE_FNO',
        security_id: '12345',
        side: 'long_ce',
        qty: 50,
        entry_price: BigDecimal('100.5'),
        symbol: 'NIFTY',
        index_key: 'NIFTY'
      )

      tracker = PositionTracker.last
      expect(tracker.meta['index_key']).to eq('NIFTY')
    end

    it 'subscribes to websocket feed' do
      instrument.after_order_track!(
        instrument: instrument,
        order_no: 'ORD123456',
        segment: 'NSE_FNO',
        security_id: '12345',
        side: 'LONG',
        qty: 50,
        entry_price: BigDecimal('100.5'),
        symbol: 'NIFTY'
      )

      expect(ws_hub).to have_received(:subscribe).with(seg: 'NSE_FNO', sid: '12345')
    end

    it 'clears Redis tick cache' do
      instrument.after_order_track!(
        instrument: instrument,
        order_no: 'ORD123456',
        segment: 'NSE_FNO',
        security_id: '12345',
        side: 'LONG',
        qty: 50,
        entry_price: BigDecimal('100.5'),
        symbol: 'NIFTY'
      )

      expect(redis_cache).to have_received(:clear_tick).with(segment: 'NSE_FNO', security_id: '12345')
    end

    it 'converts security_id to string' do
      instrument.after_order_track!(
        instrument: instrument,
        order_no: 'ORD123456',
        segment: 'NSE_FNO',
        security_id: 12345,
        side: 'LONG',
        qty: 50,
        entry_price: BigDecimal('100.5'),
        symbol: 'NIFTY'
      )

      tracker = PositionTracker.last
      expect(tracker.security_id).to eq('12345')
    end
  end
end

