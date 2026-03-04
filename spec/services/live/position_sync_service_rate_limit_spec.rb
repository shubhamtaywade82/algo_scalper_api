# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PositionSyncService do
  let(:service) { described_class.instance }

  describe '#get_paper_ltp' do
    it 'throttles direct API retries after rate-limit errors' do
      tradable = double('Tradable')
      allow(tradable).to receive(:fetch_ltp_from_api_for_segment).and_return(nil)

      tracker = instance_double(
        PositionTracker,
        segment: 'NSE_FNO',
        security_id: '50074',
        watchable: nil,
        instrument: nil,
        tradable: tradable,
        order_no: 'ORD-RL-1'
      )

      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      rate_limited = false
      allow(service).to receive(:ltp_api_rate_limited?) { rate_limited }
      allow(service).to receive(:mark_ltp_api_rate_limited!) { rate_limited = true }

      calls = 0
      allow(DhanHQ::Models::MarketFeed).to receive(:ltp) do
        calls += 1
        raise StandardError, '429: Too Many Requests'
      end

      expect(service.send(:get_paper_ltp, tracker)).to be_nil
      expect(service.send(:get_paper_ltp, tracker)).to be_nil
      expect(calls).to eq(1)
    end

    it 'writes fallback API LTP into TickCache for active positions' do
      tradable = double('Tradable')
      allow(tradable).to receive(:fetch_ltp_from_api_for_segment).and_return('123.45')

      tracker = instance_double(
        PositionTracker,
        segment: 'NSE_FNO',
        security_id: '50074',
        watchable: nil,
        instrument: nil,
        tradable: tradable,
        order_no: 'ORD-CACHE-1'
      )

      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      expect(Live::TickCache).to receive(:put).with(hash_including(segment: 'NSE_FNO', security_id: '50074', ltp: 123.45))

      ltp = service.send(:get_paper_ltp, tracker)
      expect(ltp).to eq(BigDecimal('123.45'))
    end
  end
end
