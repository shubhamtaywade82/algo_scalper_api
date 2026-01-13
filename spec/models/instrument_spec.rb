# == Schema Information
#
# Table name: instruments
#
#  id                            :integer          not null, primary key
#  exchange                      :string           not null
#  segment                       :string           not null
#  security_id                   :string           not null
#  isin                          :string
#  instrument_code               :string
#  underlying_security_id        :string
#  underlying_symbol             :string
#  symbol_name                   :string
#  display_name                  :string
#  instrument_type               :string
#  series                        :string
#  lot_size                      :integer
#  expiry_date                   :date
#  strike_price                  :decimal(15, 5)
#  option_type                   :string
#  tick_size                     :decimal(, )
#  expiry_flag                   :string
#  bracket_flag                  :string
#  cover_flag                    :string
#  asm_gsm_flag                  :string
#  asm_gsm_category              :string
#  buy_sell_indicator            :string
#  buy_co_min_margin_per         :decimal(8, 2)
#  sell_co_min_margin_per        :decimal(8, 2)
#  buy_co_sl_range_max_perc      :decimal(8, 2)
#  sell_co_sl_range_max_perc     :decimal(8, 2)
#  buy_co_sl_range_min_perc      :decimal(8, 2)
#  sell_co_sl_range_min_perc     :decimal(8, 2)
#  buy_bo_min_margin_per         :decimal(8, 2)
#  sell_bo_min_margin_per        :decimal(8, 2)
#  buy_bo_sl_range_max_perc      :decimal(8, 2)
#  sell_bo_sl_range_max_perc     :decimal(8, 2)
#  buy_bo_sl_range_min_perc      :decimal(8, 2)
#  sell_bo_sl_min_range          :decimal(8, 2)
#  buy_bo_profit_range_max_perc  :decimal(8, 2)
#  sell_bo_profit_range_max_perc :decimal(8, 2)
#  buy_bo_profit_range_min_perc  :decimal(8, 2)
#  sell_bo_profit_range_min_perc :decimal(8, 2)
#  mtf_leverage                  :decimal(8, 2)
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_instruments_on_instrument_code                    (instrument_code)
#  index_instruments_on_symbol_name                        (symbol_name)
#  index_instruments_on_underlying_symbol_and_expiry_date  (underlying_symbol,expiry_date)
#  index_instruments_unique                                (security_id,symbol_name,exchange,segment) UNIQUE
#

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instrument do
  let(:instrument) do
    described_class.find_or_create_by!(security_id: '13') do |inst|
      inst.assign_attributes(
        symbol_name: 'NIFTY',
        exchange: 'nse',
        segment: 'index',
        instrument_type: 'INDEX',
        instrument_code: 'index'
      )
    end
  end
  let(:order_response) { double('Order', order_id: 'ORD123456') }
  let(:redis_cache) { Live::RedisPnlCache.instance }
  let(:ws_hub) { Live::WsHub.instance }

  before do
    allow(ws_hub).to receive_messages(running?: true, subscribe: true)
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
        :nifty_position,
        instrument: instrument,
        watchable: instrument,
        security_id: instrument.security_id.to_s,
        segment: 'NSE_FNO',
        quantity: 5,
        status: 'active'
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
          :nifty_position,
          instrument: instrument,
          watchable: instrument,
          security_id: instrument.security_id.to_s,
          segment: 'NSE_FNO',
          quantity: 2,
          status: 'active'
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
