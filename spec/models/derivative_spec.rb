# == Schema Information
#
# Table name: derivatives
#
#  id                            :integer          not null, primary key
#  instrument_id                 :integer          not null
#  exchange                      :string
#  segment                       :string
#  security_id                   :string
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
#  strike_price                  :decimal(, )
#  option_type                   :string
#  tick_size                     :decimal(, )
#  expiry_flag                   :string
#  bracket_flag                  :string
#  cover_flag                    :string
#  asm_gsm_flag                  :string
#  asm_gsm_category              :string
#  buy_sell_indicator            :string
#  buy_co_min_margin_per         :decimal(, )
#  sell_co_min_margin_per        :decimal(, )
#  buy_co_sl_range_max_perc      :decimal(, )
#  sell_co_sl_range_max_perc     :decimal(, )
#  buy_co_sl_range_min_perc      :decimal(, )
#  sell_co_sl_range_min_perc     :decimal(, )
#  buy_bo_min_margin_per         :decimal(, )
#  sell_bo_min_margin_per        :decimal(, )
#  buy_bo_sl_range_max_perc      :decimal(, )
#  sell_bo_sl_range_max_perc     :decimal(, )
#  buy_bo_sl_range_min_perc      :decimal(, )
#  sell_bo_sl_min_range          :decimal(, )
#  buy_bo_profit_range_max_perc  :decimal(, )
#  sell_bo_profit_range_max_perc :decimal(, )
#  buy_bo_profit_range_min_perc  :decimal(, )
#  sell_bo_profit_range_min_perc :decimal(, )
#  mtf_leverage                  :decimal(, )
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_derivatives_on_instrument_code                    (instrument_code)
#  index_derivatives_on_instrument_id                      (instrument_id)
#  index_derivatives_on_symbol_name                        (symbol_name)
#  index_derivatives_on_underlying_symbol_and_expiry_date  (underlying_symbol,expiry_date)
#  index_derivatives_unique                                (security_id,symbol_name,exchange,segment) UNIQUE
#

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Derivative do
  let(:instrument) do
    Instrument.find_or_create_by!(security_id: '13') do |inst|
      inst.assign_attributes(
        symbol_name: 'NIFTY',
        exchange: 'nse',
        segment: 'index',
        instrument_type: 'INDEX',
        instrument_code: 'index'
      )
    end
  end
  let(:derivative) do
    create(:derivative, :nifty_call_option, instrument: instrument, security_id: '60001', lot_size: 25)
  end
  let(:order_response) { double('Order', order_id: 'ORD654321') }
  let(:redis_cache) { Live::RedisPnlCache.instance }
  let(:ws_hub) { Live::WsHub.instance }

  before do
    allow(ws_hub).to receive_messages(running?: true, subscribe: true)
    allow(redis_cache).to receive(:clear_tick)
    allow(redis_cache).to receive(:fetch_tick).and_return(nil)
    allow(Orders.config).to receive(:place_market).and_return(order_response)
  end

  describe '#buy_option!' do
    before do
      allow(derivative).to receive(:resolve_ltp).and_return(BigDecimal('120.75'))
    end

    context 'when quantity is provided' do
      it 'uses provided quantity and places order' do
        expect(Orders.config).to receive(:place_market).with(
          side: 'buy',
          segment: derivative.exchange_segment,
          security_id: derivative.security_id.to_s,
          qty: 50,
          meta: hash_including(
            :client_order_id,
            ltp: BigDecimal('120.75'),
            product_type: 'INTRADAY'
          )
        ).and_return(order_response)

        expect(derivative).to receive(:after_order_track!).with(
          instrument: instrument,
          order_no: 'ORD654321',
          segment: derivative.exchange_segment,
          security_id: derivative.security_id.to_s,
          side: 'long_ce',
          qty: 50,
          entry_price: BigDecimal('120.75'),
          symbol: derivative.symbol_name,
          index_key: nil
        ).and_return(instance_double(PositionTracker))

        result = derivative.buy_option!(qty: 50)
        expect(result).to eq(order_response)
      end
    end

    context 'when quantity is nil or zero' do
      it 'calculates quantity via Capital::Allocator' do
        index_cfg = { key: 'NIFTY', segment: 'IDX_I' }
        allow(Capital::Allocator).to receive(:qty_for).and_return(75)

        expect(Orders.config).to receive(:place_market).with(
          side: 'buy',
          segment: derivative.exchange_segment,
          security_id: derivative.security_id.to_s,
          qty: 75,
          meta: hash_including(:client_order_id, ltp: BigDecimal('120.75'), product_type: 'INTRADAY')
        ).and_return(order_response)

        allow(derivative).to receive(:after_order_track!).and_return(instance_double(PositionTracker))

        derivative.buy_option!(index_cfg: index_cfg)

        expect(Capital::Allocator).to have_received(:qty_for).with(
          index_cfg: index_cfg,
          entry_price: 120.75,
          derivative_lot_size: 25,
          scale_multiplier: 1
        )
      end

      it 'includes index_key in tracker when index_cfg provided' do
        index_cfg = { key: 'NIFTY', segment: 'IDX_I' }
        allow(Capital::Allocator).to receive(:qty_for).and_return(75)
        allow(Orders.config).to receive(:place_market).and_return(order_response)

        expect(derivative).to receive(:after_order_track!).with(
          instrument: instrument,
          order_no: 'ORD654321',
          segment: derivative.exchange_segment,
          security_id: derivative.security_id.to_s,
          side: 'long_ce',
          qty: 75,
          entry_price: BigDecimal('120.75'),
          symbol: derivative.symbol_name,
          index_key: 'NIFTY'
        ).and_return(instance_double(PositionTracker))

        derivative.buy_option!(index_cfg: index_cfg)
      end

      it 'uses long_pe for put options' do
        put_derivative = create(:derivative, :nifty_put_option, instrument: instrument, security_id: '60002',
                                                                lot_size: 25)
        allow(put_derivative).to receive(:resolve_ltp).and_return(BigDecimal('80.50'))
        allow(Capital::Allocator).to receive(:qty_for).and_return(50)
        allow(Orders.config).to receive(:place_market).and_return(order_response)

        expect(put_derivative).to receive(:after_order_track!).with(
          hash_including(side: 'long_pe')
        ).and_return(instance_double(PositionTracker))

        put_derivative.buy_option!
      end
    end

    context 'when LTP is unavailable' do
      it 'raises error' do
        allow(derivative).to receive(:resolve_ltp).and_return(nil)

        expect do
          derivative.buy_option!(qty: 50)
        end.to raise_error('LTP unavailable')
      end
    end

    context 'when segment or security_id is missing' do
      it 'raises error for missing segment' do
        allow(derivative).to receive(:exchange_segment).and_return('')

        expect do
          derivative.buy_option!(qty: 50)
        end.to raise_error('Derivative missing segment/security_id')
      end

      it 'raises error for missing security_id' do
        allow(derivative).to receive(:security_id).and_return('')

        expect do
          derivative.buy_option!(qty: 50)
        end.to raise_error('Derivative missing segment/security_id')
      end
    end

    context 'when quantity is zero or negative' do
      it 'returns nil when calculated quantity is zero' do
        allow(Capital::Allocator).to receive(:qty_for).and_return(0)

        expect(Orders.config).not_to receive(:place_market)

        result = derivative.buy_option!
        expect(result).to be_nil
      end

      it 'returns nil when provided quantity is zero' do
        # Mock Capital::Allocator to return 0 so place_market is not called
        allow(Capital::Allocator).to receive(:qty_for).and_return(0)
        expect(Orders.config).not_to receive(:place_market)

        result = derivative.buy_option!(qty: 0)
        expect(result).to be_nil
      end
    end

    context 'when order placement fails' do
      it 'returns nil when order response has no order_id' do
        bad_response = double('Order', order_id: nil)
        allow(Orders.config).to receive(:place_market).and_return(bad_response)

        result = derivative.buy_option!(qty: 50)
        expect(result).to be_nil
      end

      it 'returns nil when order response does not respond to order_id' do
        bad_response = double('BadResponse')
        allow(Orders.config).to receive(:place_market).and_return(bad_response)

        result = derivative.buy_option!(qty: 50)
        expect(result).to be_nil
      end
    end

    context 'with custom product_type' do
      it 'uses provided product_type' do
        allow(Orders.config).to receive(:place_market).and_return(order_response)
        allow(derivative).to receive(:after_order_track!).and_return(instance_double(PositionTracker))

        expect(Orders.config).to receive(:place_market).with(
          hash_including(meta: hash_including(product_type: 'CNC'))
        )

        derivative.buy_option!(qty: 50, product_type: 'CNC')
      end
    end
  end

  describe '#sell_option!' do
    let(:active_tracker) do
      create(
        :position_tracker,
        :nifty_position,
        instrument: instrument,
        watchable: derivative,
        security_id: derivative.security_id.to_s,
        segment: 'NSE_FNO',
        quantity: 50,
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
          segment: derivative.exchange_segment,
          security_id: derivative.security_id.to_s,
          qty: 25,
          meta: hash_including(:client_order_id)
        ).and_return(order_response)

        result = derivative.sell_option!(qty: 25)
        expect(result).to eq(order_response)
      end
    end

    context 'when quantity is nil' do
      it 'uses sum of active PositionTracker quantities' do
        create(
          :position_tracker,
          :nifty_position,
          instrument: instrument,
          watchable: derivative,
          security_id: derivative.security_id.to_s,
          segment: 'NSE_FNO',
          quantity: 25,
          status: 'active'
        )

        expect(Orders.config).to receive(:place_market).with(
          side: 'sell',
          segment: derivative.exchange_segment,
          security_id: derivative.security_id.to_s,
          qty: 75, # 50 + 25
          meta: hash_including(:client_order_id)
        ).and_return(order_response)

        derivative.sell_option!
      end
    end

    context 'when no active positions exist' do
      it 'returns nil' do
        PositionTracker.where(instrument_id: instrument.id, security_id: derivative.security_id.to_s).delete_all

        expect(Orders.config).not_to receive(:place_market)

        result = derivative.sell_option!
        expect(result).to be_nil
      end
    end

    context 'when segment or security_id is missing' do
      it 'raises error for missing segment' do
        allow(derivative).to receive(:exchange_segment).and_return('')

        expect do
          derivative.sell_option!(qty: 50)
        end.to raise_error('Derivative missing segment/security_id')
      end

      it 'raises error for missing security_id' do
        allow(derivative).to receive(:security_id).and_return('')

        expect do
          derivative.sell_option!(qty: 50)
        end.to raise_error('Derivative missing segment/security_id')
      end
    end

    context 'when quantity is zero or negative' do
      it 'returns nil when provided quantity is zero' do
        # Clear existing trackers to ensure no active positions
        PositionTracker.where(instrument_id: instrument.id, security_id: derivative.security_id.to_s).delete_all
        expect(Orders.config).not_to receive(:place_market)

        result = derivative.sell_option!(qty: 0)
        expect(result).to be_nil
      end
    end
  end
end
