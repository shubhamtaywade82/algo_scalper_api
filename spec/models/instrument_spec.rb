# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instrument, type: :model do
  let(:instrument) { create(:instrument, :nifty_index, security_id: '13') }
  let(:order_response) { double('Order', order_id: 'ORD123456') }
  let(:redis_cache) { Live::RedisPnlCache.instance }
  let(:ws_hub) { Live::WsHub.instance }

  before do
    allow(ws_hub).to receive(:running?).and_return(true)
    allow(ws_hub).to receive(:subscribe).and_return(true)
    allow(redis_cache).to receive(:clear_tick)
    allow(redis_cache).to receive(:fetch_tick).and_return(nil)
    allow(Orders.config).to receive(:place_market).and_return(order_response)
  end

  describe '#buy_market!' do
    before do
      allow(instrument).to receive(:resolve_ltp).and_return(BigDecimal('200.5'))
    end

    context 'when quantity is provided' do
      it 'uses provided quantity and places order' do
        expect(Orders.config).to receive(:place_market).with(
          side: 'buy',
          segment: instrument.exchange_segment,
          security_id: instrument.security_id.to_s,
          qty: 2,
          meta: hash_including(
            :client_order_id,
            ltp: BigDecimal('200.5'),
            product_type: 'INTRADAY'
          )
        ).and_return(order_response)

        expect(instrument).to receive(:after_order_track!).with(
          instrument: instrument,
          order_no: 'ORD123456',
          segment: instrument.exchange_segment,
          security_id: instrument.security_id.to_s,
          side: 'LONG',
          qty: 2,
          entry_price: BigDecimal('200.5'),
          symbol: instrument.symbol_name
        ).and_return(instance_double(PositionTracker))

        result = instrument.buy_market!(qty: 2)
        expect(result).to eq(order_response)
      end
    end

    context 'when quantity is nil' do
      it 'defaults to quantity 1' do
        expect(Orders.config).to receive(:place_market).with(
          hash_including(qty: 1)
        ).and_return(order_response)

        allow(instrument).to receive(:after_order_track!).and_return(instance_double(PositionTracker))

        instrument.buy_market!
      end
    end

    context 'when LTP is unavailable' do
      it 'raises error' do
        allow(instrument).to receive(:resolve_ltp).and_return(nil)

        expect do
          instrument.buy_market!(qty: 1)
        end.to raise_error('LTP unavailable')
      end
    end

    context 'when segment or security_id is missing' do
      it 'raises error for missing segment' do
        allow(instrument).to receive(:exchange_segment).and_return('')

        expect do
          instrument.buy_market!(qty: 1)
        end.to raise_error('Instrument missing segment/security_id')
      end

      it 'raises error for missing security_id' do
        allow(instrument).to receive(:security_id).and_return('')

        expect do
          instrument.buy_market!(qty: 1)
        end.to raise_error('Instrument missing segment/security_id')
      end
    end

    context 'when order placement fails' do
      it 'returns nil when order response has no order_id' do
        bad_response = double('Order', order_id: nil)
        allow(Orders.config).to receive(:place_market).and_return(bad_response)

        result = instrument.buy_market!(qty: 1)
        expect(result).to be_nil
      end

      it 'returns nil when order response does not respond to order_id' do
        bad_response = double('BadResponse')
        allow(Orders.config).to receive(:place_market).and_return(bad_response)

        result = instrument.buy_market!(qty: 1)
        expect(result).to be_nil
      end
    end

    context 'with custom product_type' do
      it 'uses provided product_type' do
        allow(instrument).to receive(:after_order_track!).and_return(instance_double(PositionTracker))

        expect(Orders.config).to receive(:place_market).with(
          hash_including(meta: hash_including(product_type: 'CNC'))
        )

        instrument.buy_market!(qty: 1, product_type: 'CNC')
      end
    end
  end

  describe '#sell_market!' do
    let(:active_tracker) do
      create(
        :position_tracker,
        instrument: instrument,
        security_id: instrument.security_id.to_s,
        quantity: 5,
        status: PositionTracker::STATUSES[:active]
      )
    end

    before do
      active_tracker
    end

    context 'when quantity is provided' do
      it 'uses provided quantity' do
        expect(Orders.config).to receive(:place_market).with(
          side: 'sell',
          segment: instrument.exchange_segment,
          security_id: instrument.security_id.to_s,
          qty: 3,
          meta: hash_including(:client_order_id)
        ).and_return(order_response)

        result = instrument.sell_market!(qty: 3)
        expect(result).to eq(order_response)
      end
    end

    context 'when quantity is nil' do
      it 'uses sum of active PositionTracker quantities' do
        create(
          :position_tracker,
          instrument: instrument,
          security_id: instrument.security_id.to_s,
          quantity: 2,
          status: PositionTracker::STATUSES[:active]
        )

        expect(Orders.config).to receive(:place_market).with(
          side: 'sell',
          segment: instrument.exchange_segment,
          security_id: instrument.security_id.to_s,
          qty: 7, # 5 + 2
          meta: hash_including(:client_order_id)
        ).and_return(order_response)

        instrument.sell_market!
      end
    end

    context 'when no active positions exist' do
      it 'returns nil' do
        PositionTracker.where(instrument_id: instrument.id, security_id: instrument.security_id.to_s).delete_all

        expect(Orders.config).not_to receive(:place_market)

        result = instrument.sell_market!
        expect(result).to be_nil
      end
    end

    context 'when segment or security_id is missing' do
      it 'raises error for missing segment' do
        allow(instrument).to receive(:exchange_segment).and_return('')

        expect do
          instrument.sell_market!(qty: 1)
        end.to raise_error('Instrument missing segment/security_id')
      end

      it 'raises error for missing security_id' do
        allow(instrument).to receive(:security_id).and_return('')

        expect do
          instrument.sell_market!(qty: 1)
        end.to raise_error('Instrument missing segment/security_id')
      end
    end

    context 'when quantity is zero or negative' do
      it 'returns nil when provided quantity is zero' do
        # Clear existing trackers
        PositionTracker.where(instrument_id: instrument.id, security_id: instrument.security_id.to_s).delete_all
        expect(Orders.config).not_to receive(:place_market)

        result = instrument.sell_market!(qty: 0)
        expect(result).to be_nil
      end
    end
  end
end

