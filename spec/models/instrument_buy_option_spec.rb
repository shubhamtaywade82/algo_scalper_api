# frozen_string_literal: true

require 'rails_helper'

# Behavioral contract for Instrument#buy_option! / #sell_option! — ported
# from the legacy Derivative model when the derivative master was
# consolidated into instruments (review 2026-09).
RSpec.describe Instrument do
  let(:underlying) do
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
  let(:option) do
    create(:instrument, :nifty_call_option, security_id: '60001', lot_size: 25,
                                            underlying_instrument: underlying)
  end
  let(:order_response) { double('Order', order_id: 'ORD654321') }
  let(:redis_cache) { Live::RedisPnlCache.instance }
  let(:ws_hub) { Live::WsHub.instance }

  before do
    allow(ws_hub).to receive_messages(running?: true, subscribe: true)
    allow(redis_cache).to receive(:clear_tick)
    allow(redis_cache).to receive(:fetch_tick).and_return(nil)
    allow(Orders.config.gateway).to receive(:place_market).and_return(order_response)
  end

  describe '#buy_option!' do
    before do
      allow(option).to receive(:resolve_ltp).and_return(BigDecimal('120.75'))
    end

    context 'when quantity is provided' do
      it 'places the order and records a first-class execution' do
        expect(Orders.config.gateway).to receive(:place_market).with(
          side: 'buy',
          segment: option.exchange_segment,
          security_id: option.security_id.to_s,
          qty: 50,
          meta: hash_including(
            :client_order_id,
            ltp: BigDecimal('120.75'),
            product_type: 'NORMAL'
          )
        ).and_return(order_response)

        allow(option).to receive(:after_order_track!).and_return(instance_double(PositionTracker))

        result = option.buy_option!(qty: 50)
        expect(result).to eq(order_response)
      end
    end

    context 'with explicit auto_size (allocator sizing policy)' do
      it 'calculates quantity via Capital::Allocator and labels the side by option type' do
        index_cfg = { key: 'NIFTY', segment: 'IDX_I' }
        allow(Capital::Allocator).to receive(:qty_for).and_return(75)

        expect(option).to receive(:after_order_track!).with(
          hash_including(side: 'long_ce', qty: 75, security_id: option.security_id.to_s)
        ).and_return(instance_double(PositionTracker))

        option.buy_option!(auto_size: true, index_cfg: index_cfg)

        expect(Capital::Allocator).to have_received(:qty_for).with(
          index_cfg: index_cfg,
          entry_price: 120.75,
          derivative_lot_size: 25,
          scale_multiplier: 1
        )
      end

      it 'uses long_pe for put options' do
        put_option = create(:instrument, :nifty_put_option, security_id: '60002', lot_size: 25,
                                                            underlying_instrument: underlying)
        allow(put_option).to receive(:resolve_ltp).and_return(BigDecimal('80.50'))
        allow(Capital::Allocator).to receive(:qty_for).and_return(50)

        expect(put_option).to receive(:after_order_track!).with(
          hash_including(side: 'long_pe')
        ).and_return(instance_double(PositionTracker))

        put_option.buy_option!(auto_size: true, index_cfg: { key: 'NIFTY', segment: 'IDX_I' })
      end
    end

    context 'when quantity is absent and auto_size is not requested' do
      it 'raises Errors::InvalidQuantity — sizing is never inferred' do
        expect(Orders.config.gateway).not_to receive(:place_market)

        expect { option.buy_option! }.to raise_error(Errors::InvalidQuantity)
        expect { option.buy_option!(index_cfg: { key: 'NIFTY' }) }.to raise_error(Errors::InvalidQuantity)
      end
    end

    context 'auto_size without index_cfg' do
      it 'raises Errors::ConfigurationError — refuses to manufacture a config' do
        expect(Capital::Allocator).not_to receive(:qty_for)

        expect { option.buy_option!(auto_size: true) }.to raise_error(Errors::ConfigurationError)
      end
    end

    context 'when LTP is unavailable' do
      it 'raises error' do
        allow(option).to receive(:resolve_ltp).and_return(nil)

        expect do
          option.buy_option!(qty: 50)
        end.to raise_error('LTP unavailable')
      end
    end

    context 'when segment or security_id is missing' do
      it 'raises error for missing segment' do
        allow(option).to receive(:exchange_segment).and_return('')

        expect do
          option.buy_option!(qty: 50)
        end.to raise_error('Instrument missing segment/security_id')
      end

      it 'raises error for missing security_id' do
        allow(option).to receive(:security_id).and_return('')

        expect do
          option.buy_option!(qty: 50)
        end.to raise_error('Instrument missing segment/security_id')
      end
    end

    context 'when the allocator returns no usable quantity' do
      it 'raises Errors::InvalidQuantity instead of silently skipping the order' do
        allow(Capital::Allocator).to receive(:qty_for).and_return(0)

        expect(Orders.config.gateway).not_to receive(:place_market)

        expect { option.buy_option!(auto_size: true, index_cfg: { key: 'NIFTY' }) }
          .to raise_error(Errors::InvalidQuantity)
      end
    end

    context 'when order placement fails' do
      it 'returns nil when order response has no order_id' do
        bad_response = double('Order', order_id: nil)
        allow(Orders.config.gateway).to receive(:place_market).and_return(bad_response)

        expect(option.buy_option!(qty: 50)).to be_nil
      end
    end

    context 'with a paper gateway response' do
      let(:tracker) { instance_double(PositionTracker, paper?: true, symbol: 'NIFTY', security_id: '60001', id: 99, iv_percentile: nil, short_position?: false, margin_required: 0, order_no: 'PAPER-1', meta: {}) }

      it 'books the ledger at the SIMULATED fill price, not the LTP' do
        paper_response = { success: true, order_id: 'PAPER-1', paper: true, fill_price: 121.05, bid: 120.80, ask: 121.00 }
        allow(Orders.config.gateway).to receive(:place_market).and_return(paper_response)
        allow(option).to receive(:after_order_track!).and_return(tracker)
        # The InstanceDouble tracker cannot be assigned to the Execution
        # belongs_to, so record_from_order! self-isolates and returns nil -
        # stub the recorded execution carrying the simulated fill instead.
        execution = instance_double(Execution, fill_price: BigDecimal('121.05'))
        allow(Execution).to receive(:record_from_order!).and_return(execution)

        # LTP is 120.75 (stubbed below in the outer context) - the assertion
        # discriminates the ledger booking between the simulated fill and LTP.
        expect(Ledger::EntryPoster).to receive(:post!).with(
          hash_including(fill_price: BigDecimal('121.05'), quantity: 50, order_no: 'PAPER-1')
        ).and_return(Ledger::EntryPoster::Result.new(status: :posted))

        option.buy_option!(qty: 50)
      end
    end
  end

  describe '#sell_option!' do
    let(:active_tracker) do
      create(
        :position_tracker,
        :nifty_position,
        instrument: underlying,
        watchable: option,
        security_id: option.security_id.to_s,
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
        expect(Orders.config.gateway).to receive(:place_market).with(
          side: 'sell',
          segment: option.exchange_segment,
          security_id: option.security_id.to_s,
          qty: 25,
          meta: hash_including(:client_order_id)
        ).and_return(order_response)

        result = option.sell_option!(qty: 25)
        expect(result).to eq(order_response)
      end
    end

    context 'when quantity is nil' do
      it 'raises Errors::InvalidQuantity — whole-position exit is the explicit close_position!' do
        expect(Orders.config.gateway).not_to receive(:place_market)

        expect { option.sell_option! }.to raise_error(Errors::InvalidQuantity)
      end
    end

    context 'close_position! (explicit whole-position exit)' do
      it 'sells the sum of active PositionTracker quantities' do
        create(
          :position_tracker,
          :nifty_position,
          instrument: underlying,
          watchable: option,
          security_id: option.security_id.to_s,
          segment: 'NSE_FNO',
          quantity: 25,
          status: 'active'
        )

        expect(Orders.config.gateway).to receive(:place_market).with(
          side: 'sell',
          segment: option.exchange_segment,
          security_id: option.security_id.to_s,
          qty: 75, # 50 + 25
          meta: hash_including(:client_order_id, close_position: true)
        ).and_return(order_response)

        option.close_position!
      end

      it 'returns nil when there is no active position (documented outcome)' do
        PositionTracker.where(security_id: option.security_id.to_s).delete_all

        expect(Orders.config.gateway).not_to receive(:place_market)

        expect(option.close_position!).to be_nil
      end
    end
  end
end
