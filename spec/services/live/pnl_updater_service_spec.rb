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

    redis_cache = instance_double(Live::RedisPnlCache, store_pnl: true, fetch_pnl: { ltp: 120.0 })
    allow(Live::RedisPnlCache).to receive(:instance).and_return(redis_cache)

    allow(redis_cache).to receive(:store_pnl)

    service.cache_intermediate_pnl(tracker_id: tracker.id, pnl: 2000.0, pnl_pct: 0.2, ltp: 120.0, hwm: 2000.0)

    # Flush synchronously
    service.flush_now!

    data = redis_cache.fetch_pnl(tracker.id)
    expect(redis_cache).to have_received(:store_pnl).with(hash_including(tracker_id: tracker.id, ltp: 120.0))
    expect(data).not_to be_nil
    expect(data[:ltp].to_f).to be_within(0.001).of(120.0)
  end

  it 'broadcasts pnl_stale when tick ltp is missing' do
    Rails.cache.delete("pnl_stale:#{tracker.id}")

    allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: nil))
    allow(ActionCable.server).to receive(:broadcast)

    service.cache_intermediate_pnl(tracker_id: tracker.id, pnl: nil, pnl_pct: nil, ltp: nil, hwm: nil, hwm_pnl_pct: nil)
    service.flush_now!

    expect(ActionCable.server).to have_received(:broadcast).with(
      'positions',
      hash_including(type: 'pnl_stale', id: tracker.id)
    )
  end

  describe 'ActionCable broadcasts' do
    let(:tracker) { create(:position_tracker, entry_price: 100.0, quantity: 1, segment: 'NSE_FNO', security_id: '50073') }

    before do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      allow(service).to receive(:start!).and_return(true)
      service.cache_intermediate_pnl(tracker_id: tracker.id, ltp: nil)
    end

    context 'when tick_ltp is nil' do
      before do
        Rails.cache.delete("pnl_stale:#{tracker.id}")
        allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      end

      it 'broadcasts pnl_stale for the tracker' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'positions',
          { type: 'pnl_stale', id: tracker.id }
        )
        service.flush_now!
      end
    end

    context 'when tick_ltp is valid' do
      before do
        allow(Live::TickQuery).to receive(:for_security).and_return(double(ltp: 110.0))
        service.cache_intermediate_pnl(tracker_id: tracker.id, ltp: 110.0)
      end

      it 'broadcasts pnl_update with ltp_stale: false' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'positions',
          hash_including(type: 'pnl_update', ltp_stale: false)
        )
        service.flush_now!
      end
    end
  end
end
