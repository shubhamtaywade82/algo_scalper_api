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

    it 'does not overwrite the final PnL of a tracker exited after it was cached' do
      tracker = create(:position_tracker, :active, paper: true, entry_price: 100, quantity: 10, segment: 'NSE_FNO')
      stale_copy = PositionTracker.find(tracker.id)
      tracker.update_columns(status: 'exited', last_pnl_rupees: 160) # rubocop:disable Rails/SkipsModelValidations

      allow(Live::TickQuery).to receive(:for_security).and_return(Struct.new(:ltp).new(130.0))
      redis_pnl_cache = instance_double(Live::RedisPnlCache, store_pnl: true)
      allow(Live::RedisPnlCache).to receive(:instance).and_return(redis_pnl_cache)

      service.send(:refresh_tracker, stale_copy)

      expect(tracker.reload.last_pnl_rupees).to eq(160)
      expect(redis_pnl_cache).not_to have_received(:store_pnl)
    end

    it 'updates PnL for a still-active tracker' do
      tracker = create(:position_tracker, :active, paper: true, entry_price: 100, quantity: 10, segment: 'NSE_FNO')
      allow(Live::TickQuery).to receive(:for_security).and_return(Struct.new(:ltp).new(130.0))
      allow(BrokerFeeCalculator).to receive(:net_pnl) { |gross, **| gross }
      allow(Live::RedisPnlCache).to receive(:instance).and_return(instance_double(Live::RedisPnlCache, store_pnl: true))

      expected_pnl = (130 - tracker.entry_price) * tracker.quantity

      service.send(:refresh_tracker, tracker)

      expect(tracker.reload.last_pnl_rupees).to eq(expected_pnl)
    end
  end
end
