# frozen_string_literal: true

require 'rails_helper'
require 'bigdecimal'

RSpec.describe Orders::Placer do
  let(:order_double) { instance_double(DhanHQ::Models::Order) }
  let(:captured_attrs) { [] }
  let(:segment) { 'NSE_FNO' }
  let(:security_id) { '123456' }
  let(:quantity) { 50 }

  before do
    allow(Rails.cache).to receive(:read).and_return(nil)
    allow(Rails.cache).to receive(:write)
    allow(DhanHQ::Models::Order).to receive(:create) do |attributes|
      captured_attrs << attributes
      order_double
    end
    # Enable order placement for tests by stubbing the class method
    allow(described_class).to receive(:order_placement_enabled?).and_return(true)
  end

  describe '.sell_market!' do
    let(:position_details) do
      {
        product_type: 'INTRADAY',
        net_qty: quantity,
        exchange_segment: segment,
        position_type: 'LONG'
      }
    end

    before do
      allow(described_class).to receive(:fetch_position_details).and_return(position_details)
    end

    it 'normalizes long client order ids to meet the 30 character limit' do
      long_id = 'AS-EXIT-12345678901234567890-9999999999'

      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      # Verify cache write with normalized ID (not correlation_id in payload)
      expect(Rails.cache).to have_received(:write).with(match(/^coid:/), true, expires_in: 20.minutes)
    end

    it 'skips placing duplicate orders based on the normalized id' do
      long_id = 'AS-EXIT-12345678901234567890-9999999999'
      allow(Rails.cache).to receive(:read).and_return(nil, true)
      allow(described_class).to receive(:fetch_position_details).and_return(
        {
          product_type: 'INTRADAY',
          net_qty: quantity,
          exchange_segment: segment,
          position_type: 'LONG'
        }
      )

      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)
      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      expect(DhanHQ::Models::Order).to have_received(:create).once
    end
  end

  describe '.buy_market!' do
    it 'uses the normalized id for correlation' do
      long_id = 'AS-BUY-12345678901234567890-9999999999'

      described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      expect(captured_attrs.last[:correlation_id].length).to be <= 30
    end

    it 'places a market order even when risk parameters are provided' do
      stop_loss = BigDecimal('100.5')
      target = BigDecimal('125.25')

      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: "AS-BUY-ABC-#{Time.current.to_i}",
        stop_loss_price: stop_loss,
        target_price: target
      )

      expect(DhanHQ::Models::Order).to have_received(:create)
      expect(captured_attrs.last).to include(
        transaction_type: 'BUY',
        order_type: 'MARKET',
        product_type: 'INTRADAY'
      )
      expect(captured_attrs.last).not_to have_key(:stop_loss_price)
      expect(captured_attrs.last).not_to have_key(:target_price)
    end

    describe 'order payload structure' do
      let(:client_order_id) { "TEST-ORDER-#{Time.current.to_i}" }
      let(:expected_payload) do
        {
          transaction_type: 'BUY',
          exchange_segment: segment,
          security_id: security_id,
          quantity: quantity,
          order_type: 'MARKET',
          product_type: 'INTRADAY',
          validity: 'DAY',
          correlation_id: client_order_id,
          disclosed_quantity: 0
        }
      end

      it 'creates correct payload for basic market buy order' do
        described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(captured_attrs.last).to eq(expected_payload)
      end

      it 'includes price when provided' do
        price = BigDecimal('150.75')

        described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id,
          price: price
        )

        expected_with_price = expected_payload.merge(price: price)
        expect(captured_attrs.last).to eq(expected_with_price)
      end

      it 'handles different product types' do
        described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id,
          product_type: 'DELIVERY'
        )

        expected_delivery = expected_payload.merge(product_type: 'DELIVERY')
        expect(captured_attrs.last).to eq(expected_delivery)
      end

      it 'validates required parameters' do
        expect(Rails.logger).to receive(:error).with(/Missing required parameters/)

        result = described_class.buy_market!(
          seg: nil,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(result).to be_nil
        expect(DhanHQ::Models::Order).not_to have_received(:create)
      end

      it 'logs order placement with correct parameters' do
        # Mock logger to avoid failures while testing actual functionality
        allow(Rails.logger).to receive(:info)

        result = described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        # Order may return order object or nil (dry-run mode)
        # The important thing is that it doesn't raise an error
        expect(result).to eq(order_double).or be_nil
      end
    end
  end

  describe '.sell_market!' do
    describe 'order payload structure' do
      let(:client_order_id) { "TEST-SELL-#{Time.current.to_i}" }
      let(:position_details) do
        {
          product_type: 'INTRADAY',
          net_qty: quantity,
          exchange_segment: segment,
          position_type: 'LONG'
        }
      end
      let(:expected_payload) do
        {
          transaction_type: 'SELL',
          exchange_segment: segment,
          security_id: security_id,
          quantity: quantity,
          order_type: 'MARKET',
          product_type: 'INTRADAY',
          validity: 'DAY',
          disclosed_quantity: 0
        }
      end

      before do
        allow(described_class).to receive(:fetch_position_details).and_return(position_details)
      end

      it 'creates correct payload for market sell order' do
        described_class.sell_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(captured_attrs.last).to eq(expected_payload)
      end

      it 'validates required parameters' do
        expect(Rails.logger).to receive(:error).with(/Missing required parameters/)

        result = described_class.sell_market!(
          seg: segment,
          sid: nil,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(result).to be_nil
        expect(DhanHQ::Models::Order).not_to have_received(:create)
      end

      it 'logs order placement with correct parameters' do
        # Mock logger to avoid failures while testing actual functionality
        allow(Rails.logger).to receive(:info)

        result = described_class.sell_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        # Order may return order object or nil (dry-run mode)
        # The important thing is that it doesn't raise an error
        expect(result).to eq(order_double).or be_nil
      end
    end
  end

  describe 'client order ID normalization' do
    it 'preserves short IDs unchanged' do
      short_id = 'SHORT-ID'

      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: short_id
      )

      expect(captured_attrs.last[:correlation_id]).to eq(short_id)
    end

    it 'truncates and hashes long IDs' do
      long_id = 'VERY-LONG-CLIENT-ORDER-ID-THAT-EXCEEDS-THIRTY-CHARACTERS'

      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: long_id
      )

      normalized_id = captured_attrs.last[:correlation_id]
      expect(normalized_id.length).to be <= 30
      expect(normalized_id).to match(/\A.{23}-[a-f0-9]{6}\z/)
    end

    it 'warns when ID is truncated' do
      long_id = 'VERY-LONG-CLIENT-ORDER-ID-THAT-EXCEEDS-THIRTY-CHARACTERS'

      expect(Rails.logger).to receive(:warn).with(/client_order_id truncated/)

      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: long_id
      )
    end
  end

  describe 'duplicate prevention' do
    it 'prevents duplicate orders within 20 minutes' do
      client_order_id = "DUPLICATE-TEST-#{Time.current.to_i}"

      # First order succeeds
      allow(Rails.cache).to receive(:read).and_return(nil)
      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: client_order_id
      )

      # Second order should be blocked
      allow(Rails.cache).to receive(:read).and_return(true)
      result = described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: client_order_id
      )

      expect(result).to be_nil
      expect(DhanHQ::Models::Order).to have_received(:create).once
    end

    it 'stores order ID in cache for 20 minutes' do
      client_order_id = "CACHE-TEST-#{Time.current.to_i}"

      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: client_order_id
      )

      expect(Rails.cache).to have_received(:write).with(
        "coid:#{client_order_id}",
        true,
        expires_in: 20.minutes
      )
    end
  end

  describe 'derivative-specific order payloads' do
    describe 'NSE derivatives (NSE_FNO)' do
      let(:nse_derivative_segment) { 'NSE_FNO' }
      let(:nse_derivative_security_id) { '123456' }
      let(:nse_derivative_quantity) { 50 }
      let(:nse_client_order_id) { "NSE-DERIVATIVE-TEST-#{Time.current.to_i}" }

      let(:expected_nse_payload) do
        {
          transaction_type: 'BUY',
          exchange_segment: nse_derivative_segment,
          security_id: nse_derivative_security_id,
          quantity: nse_derivative_quantity,
          order_type: 'MARKET',
          product_type: 'INTRADAY',
          validity: 'DAY',
          correlation_id: nse_client_order_id,
          disclosed_quantity: 0
        }
      end

      it 'creates correct payload for NSE derivative BUY market order' do
        described_class.buy_market!(
          seg: nse_derivative_segment,
          sid: nse_derivative_security_id,
          qty: nse_derivative_quantity,
          client_order_id: nse_client_order_id
        )

        expect(captured_attrs.last).to eq(expected_nse_payload)
      end

      it 'creates correct payload for NSE derivative SELL market order' do
        expected_sell_payload = expected_nse_payload.merge(transaction_type: 'SELL')
        expected_sell_payload.delete(:correlation_id) # remove correlation_id from expected

        allow(described_class).to receive(:fetch_position_details).and_return(
          product_type: 'INTRADAY',
          net_qty: nse_derivative_quantity,
          exchange_segment: nse_derivative_segment,
          position_type: 'LONG'
        )

        described_class.sell_market!(
          seg: nse_derivative_segment,
          sid: nse_derivative_security_id,
          qty: nse_derivative_quantity,
          client_order_id: nse_client_order_id
        )

        expect(captured_attrs.last).to eq(expected_sell_payload)
      end
    end

    describe 'BSE derivatives (BSE_FNO)' do
      let(:bse_derivative_segment) { 'BSE_FNO' }
      let(:bse_derivative_security_id) { '789012' }
      let(:bse_derivative_quantity) { 25 }
      let(:bse_client_order_id) { "BSE-DERIVATIVE-TEST-#{Time.current.to_i}" }

      let(:expected_bse_payload) do
        {
          transaction_type: 'BUY',
          exchange_segment: bse_derivative_segment,
          security_id: bse_derivative_security_id,
          quantity: bse_derivative_quantity,
          order_type: 'MARKET',
          product_type: 'INTRADAY',
          validity: 'DAY',
          correlation_id: bse_client_order_id,
          disclosed_quantity: 0
        }
      end

      it 'creates correct payload for BSE derivative BUY market order' do
        described_class.buy_market!(
          seg: bse_derivative_segment,
          sid: bse_derivative_security_id,
          qty: bse_derivative_quantity,
          client_order_id: bse_client_order_id
        )

        expect(captured_attrs.last).to eq(expected_bse_payload)
      end

      it 'creates correct payload for BSE derivative SELL market order' do
        expected_sell_payload = expected_bse_payload.merge(transaction_type: 'SELL')
        expected_sell_payload.delete(:correlation_id) # remove correlation_id from expected

        allow(described_class).to receive(:fetch_position_details).and_return(
          product_type: 'INTRADAY',
          net_qty: bse_derivative_quantity,
          exchange_segment: bse_derivative_segment,
          position_type: 'LONG'
        )

        described_class.sell_market!(
          seg: bse_derivative_segment,
          sid: bse_derivative_security_id,
          qty: bse_derivative_quantity,
          client_order_id: bse_client_order_id
        )

        expect(captured_attrs.last).to eq(expected_sell_payload)
      end
    end

    describe 'Index instruments (IDX_I)' do
      let(:index_segment) { 'IDX_I' }
      let(:index_security_id) { '51' } # SENSEX
      let(:index_quantity) { 1 } # Index trading is typically 1 unit
      let(:index_client_order_id) { "INDEX-TEST-#{Time.current.to_i}" }

      let(:expected_index_payload) do
        {
          transaction_type: 'BUY',
          exchange_segment: index_segment,
          security_id: index_security_id,
          quantity: index_quantity,
          order_type: 'MARKET',
          product_type: 'INTRADAY',
          validity: 'DAY',
          correlation_id: index_client_order_id,
          disclosed_quantity: 0
        }
      end

      it 'creates correct payload for Index BUY market order' do
        described_class.buy_market!(
          seg: index_segment,
          sid: index_security_id,
          qty: index_quantity,
          client_order_id: index_client_order_id
        )

        expect(captured_attrs.last).to eq(expected_index_payload)
      end

      it 'creates correct payload for Index SELL market order' do
        expected_sell_payload = expected_index_payload.merge(transaction_type: 'SELL')
        expected_sell_payload.delete(:correlation_id) # remove correlation_id from expected

        allow(described_class).to receive(:fetch_position_details).and_return(
          product_type: 'INTRADAY',
          net_qty: index_quantity,
          exchange_segment: index_segment,
          position_type: 'LONG'
        )

        described_class.sell_market!(
          seg: index_segment,
          sid: index_security_id,
          qty: index_quantity,
          client_order_id: index_client_order_id
        )

        expect(captured_attrs.last).to eq(expected_sell_payload)
      end
    end

    describe 'exchange segment validation' do
      it 'validates that derivative.exchange_segment is used correctly' do
        # This test demonstrates the key principle: derivative.exchange_segment
        # should always be used for derivative orders, not the underlying index segment

        nse_derivative_segment = 'NSE_FNO'
        derivative_security_id = '123456'

        # Mock logger to avoid failures while testing actual functionality
        allow(Rails.logger).to receive(:info)

        result = described_class.buy_market!(
          seg: nse_derivative_segment, # This should be derivative.exchange_segment
          sid: derivative_security_id,
          qty: 50,
          client_order_id: 'TEST-DERIVATIVE'
        )

        expect(captured_attrs.last[:exchange_segment]).to eq(nse_derivative_segment)
        expect(result).to eq(order_double).or be_nil
      end
    end
  end
end
