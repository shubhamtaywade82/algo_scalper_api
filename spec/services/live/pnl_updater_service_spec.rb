# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PnlUpdaterService, :freeze_time do
  let(:service) { described_class.instance }
  let(:tracker) { create(:position_tracker, entry_price: 100.0, quantity: 1, segment: 'NSE_FNO', security_id: '50073') }

  before do
    Live::TickCache.put(segment: tracker.segment, security_id: tracker.security_id, ltp: 120.0)
    service.start!
  end

  it 'writes pnl to redis using tickcache ltp' do
    service.cache_intermediate_pnl(tracker_id: tracker.id, pnl: 2000.0, pnl_pct: 0.2, ltp: 120.0, hwm: 2000.0)
    sleep 0.5
    data = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
    expect(data).not_to be_nil
    expect(data[:ltp]).to be_within(0.001).of(120.0)
  end
end
