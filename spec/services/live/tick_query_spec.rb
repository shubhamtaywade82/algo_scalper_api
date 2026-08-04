# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::TickQuery do
  describe '.for_security' do
    it 'returns a MarketTick with decimal ltp when cache has ltp' do
      allow(Live::TickCache).to receive(:fetch).with('NSE_FNO', '12345').and_return(
        { ltp: '101.25', timestamp: Time.zone.parse('2026-01-01 09:15:00') }
      )
      allow(Live::TickCache).to receive(:ltp).with('NSE_FNO', '12345').and_return(nil)

      tick = described_class.for_security(segment: 'NSE_FNO', security_id: '12345')

      expect(tick).to be_a(MarketTick)
      expect(tick.segment).to eq('NSE_FNO')
      expect(tick.security_id).to eq('12345')
      expect(tick.ltp).to eq(BigDecimal('101.25'))
      expect(tick.timestamp).to eq(Time.zone.parse('2026-01-01 09:15:00'))
      expect(tick.oi).to eq(0)
      expect(tick.oi_change).to eq(0)
      expect(tick.bid).to be_nil
      expect(tick.ask).to be_nil
      expect(tick.volume).to eq(0)
      expect(tick.prev_close).to be_nil
    end

    it 'returns nil when no cache ltp is present' do
      allow(Live::TickCache).to receive_messages(fetch: nil, ltp: nil)

      expect(described_class.for_security(segment: 'NSE_FNO', security_id: '12345')).to be_nil
    end
  end
end
