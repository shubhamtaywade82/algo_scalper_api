# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PaperPnlRefresher do
  let(:service) { described_class.new }

  describe '#refresh_tracker' do
    it 'falls back to API LTP and updates cache + redis pnl when tick cache is empty' do
      tradable = double('Tradable', fetch_ltp_from_api_for_segment: '120.0')

      tracker = instance_double(
        PositionTracker,
        id: 101,
        segment: 'NSE_FNO',
        security_id: '45526',
        entry_price: BigDecimal(100),
        quantity: 10,
        exited?: false,
        high_water_mark_pnl: BigDecimal(0),
        tradable: tradable
      )

      allow(Live::TickQuery).to receive(:for_security).and_return(nil)
      allow(Live::TickCache).to receive(:put)
      allow(BrokerFeeCalculator).to receive(:net_pnl) { |gross, _is_exited:| gross }

      redis_pnl_cache = instance_double(Live::RedisPnlCache, store_pnl: true)
      allow(Live::RedisPnlCache).to receive(:instance).and_return(redis_pnl_cache)

      service.send(:refresh_tracker, tracker)

      expect(Live::TickCache).to have_received(:put).with(
        hash_including(segment: 'NSE_FNO', security_id: '45526', ltp: 120.0)
      )
    end
  end
end
