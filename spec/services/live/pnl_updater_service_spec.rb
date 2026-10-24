# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PnlUpdaterService, :freeze_time do
  let(:service) { described_class.instance }
  let(:tracker) { create(:position_tracker, entry_price: 100.0, quantity: 1, segment: 'NSE_FNO', security_id: '50073') }

  before do
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    Live::TickCache.put(segment: tracker.segment, security_id: tracker.security_id, ltp: 120.0)
    # Prevent background thread from starting
    allow(service).to receive(:start!).and_return(true)
  end

  it 'writes pnl to redis using tickcache ltp' do
    # Mock TickQuery to return LTP
    allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: 120.0))
    allow(Live::RedisPnlCache.instance).to receive(:store_pnl)

    service.cache_intermediate_pnl(tracker_id: tracker.id, pnl: 2000.0, pnl_pct: 0.2, ltp: 120.0, hwm: 2000.0)
    service.flush_now!

    # payload[:pnl] override (2000.0) still goes through fee deduction (₹20/order, not exited)
    expect(Live::RedisPnlCache.instance).to have_received(:store_pnl)
      .with(hash_including(pnl: 1980.0, ltp: 120.0))
  end

  it 'publishes on the same event name RiskManagerService subscribes to' do
    allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: 120.0))
    allow(Live::RedisPnlCache.instance).to receive(:store_pnl)
    allow(Core::EventBus.instance).to receive(:publish).and_call_original

    service.cache_intermediate_pnl(tracker_id: tracker.id, ltp: 120.0)
    service.flush_now!

    expect(Core::EventBus.instance).to have_received(:publish)
      .with(Core::EventBus::EVENTS[:pnl_update], hash_including(tracker_id: tracker.id))
  end

  describe 'gross pnl sign by position_side' do
    before do
      allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: 120.0))
      allow(Live::RedisPnlCache.instance).to receive(:store_pnl)
    end

    it 'computes positive pnl for a long position when price rises' do
      long_tracker = create(:position_tracker, entry_price: 100.0, quantity: 25, segment: 'NSE_FNO',
                                               security_id: '50074', position_side: 'long')

      service.cache_intermediate_pnl(tracker_id: long_tracker.id, ltp: 120.0)
      service.flush_now!

      expect(Live::RedisPnlCache.instance).to have_received(:store_pnl) do |**kwargs|
        expect(kwargs[:pnl]).to be > 0
      end
    end

    it 'computes negative pnl for a short position when price rises' do
      short_tracker = create(:position_tracker, entry_price: 100.0, quantity: 25, segment: 'NSE_FNO',
                                                security_id: '50075', position_side: 'short')

      service.cache_intermediate_pnl(tracker_id: short_tracker.id, ltp: 120.0)
      service.flush_now!

      expect(Live::RedisPnlCache.instance).to have_received(:store_pnl) do |**kwargs|
        expect(kwargs[:pnl]).to be < 0
      end
    end
  end
end
