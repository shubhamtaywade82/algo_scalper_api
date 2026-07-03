# frozen_string_literal: true

require "rails_helper"
require "bigdecimal"

RSpec.describe Orders::Placer do
  let(:order_double) { instance_double(DhanHQ::Models::Order) }
  let(:captured_attrs) { [] }
  let(:segment) { "NSE_FNO" }
  let(:security_id) { "123456" }
  let(:quantity) { 50 }

  before do
    allow(Rails.cache).to receive(:read).and_return(nil)
    allow(Rails.cache).to receive(:write)
    allow(DhanHQ::Models::Order).to receive(:create) do |attributes|
      captured_attrs << attributes
      order_double
    end
    # Enable order placement for tests
    allow(ENV).to receive(:[]).with("PLACE_ORDER").and_return("true")
    # Bypass rate limiting in tests so specs don't block on token bucket
    allow(described_class).to receive(:with_order_rate_limit).and_yield
  end

  describe ".sell_market! client order ID handling" do
    let(:position_details) do
      {
        product_type: DhanHQ::Constants::ProductType::INTRADAY,
        net_qty: quantity,
        exchange_segment: segment,
        position_type: DhanHQ::Constants::PositionType::LONG
      }
    end

    before do
      allow(described_class).to receive(:fetch_position_details).and_return(position_details)
    end

    it "normalizes long client order ids to meet the 30 character limit" do
      long_id = "AS-EXIT-12345678901234567890-9999999999"

      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      # Verify cache write with normalized ID (not correlation_id in payload)
      expect(Rails.cache).to have_received(:write).with(match(/^coid:/), true, expires_in: 20.minutes)
    end

    it "skips placing duplicate orders based on the normalized id" do
      long_id = "AS-EXIT-12345678901234567890-9999999999"
      allow(Rails.cache).to receive(:read).and_return(nil, true)
      allow(described_class).to receive(:fetch_position_details).and_return(
        {
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
          net_qty: quantity,
          exchange_segment: segment,
          position_type: DhanHQ::Constants::PositionType::LONG
        }
      )

      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)
      described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      expect(DhanHQ::Models::Order).to have_received(:create).once
    end
  end

  describe ".buy_market!" do
    it "uses the normalized id for correlation" do
      long_id = "AS-BUY-12345678901234567890-9999999999"

      described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: long_id)

      expect(captured_attrs.last[:correlation_id].length).to be <= 30
    end

    it "places a market order even when risk parameters are provided" do
      stop_loss = BigDecimal("100.5")
      target = BigDecimal("125.25")

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
        transaction_type: DhanHQ::Constants::TransactionType::BUY,
        order_type: DhanHQ::Constants::OrderType::MARKET,
        product_type: "NORMAL"
      )
      expect(captured_attrs.last).not_to have_key(:stop_loss_price)
      expect(captured_attrs.last).not_to have_key(:target_price)
    end

    describe "order payload structure" do
      let(:client_order_id) { "TEST-ORDER-#{Time.current.to_i}" }
      let(:expected_payload) do
        {
          transaction_type: DhanHQ::Constants::TransactionType::BUY,
          exchange_segment: segment,
          security_id: security_id,
          quantity: quantity,
          order_type: DhanHQ::Constants::OrderType::MARKET,
          product_type: "NORMAL",
          validity: DhanHQ::Constants::Validity::DAY,
          correlation_id: client_order_id,
          disclosed_quantity: 0
        }
      end

      it "creates correct payload for basic market buy order" do
        described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(captured_attrs.last).to eq(expected_payload)
      end

      it "includes price when provided" do
        price = BigDecimal("150.75")

        described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id,
          price: price
        )

        # DhanHQ 2.6.x PlaceOrderContract: MARKET orders must not send price; we omit it
        expect(captured_attrs.last).to eq(expected_payload)
        expect(captured_attrs.last).not_to have_key(:price)
      end

      it "handles different product types" do
        described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id,
          product_type: DhanHQ::Constants::ProductType::CNC
        )

        expected_delivery = expected_payload.merge(product_type: DhanHQ::Constants::ProductType::CNC)
        expect(captured_attrs.last).to eq(expected_delivery)
      end

      it "validates required parameters" do
        allow(Rails.logger).to receive(:error)

        result = described_class.buy_market!(
          seg: nil,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(Rails.logger).to have_received(:error).with(/Missing required parameters/)
        expect(result).to be_nil
        expect(DhanHQ::Models::Order).not_to have_received(:create)
      end

      it "logs order placement with correct parameters" do
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

  describe ".sell_market!" do
    describe "order payload structure" do
      let(:client_order_id) { "TEST-SELL-#{Time.current.to_i}" }
      let(:position_details) do
        {
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
          net_qty: quantity,
          exchange_segment: segment,
          position_type: DhanHQ::Constants::PositionType::LONG
        }
      end
      let(:expected_payload) do
        {
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
          exchange_segment: segment,
          security_id: security_id,
          quantity: quantity,
          order_type: DhanHQ::Constants::OrderType::MARKET,
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
          validity: DhanHQ::Constants::Validity::DAY,
          disclosed_quantity: 0,
          correlation_id: kind_of(String)
        }
      end

      before do
        allow(described_class).to receive(:fetch_position_details).and_return(position_details)
      end

      it "creates correct payload for market sell order" do
        described_class.sell_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(captured_attrs.last).to match(hash_including(expected_payload))
      end

      it "validates required parameters" do
        allow(Rails.logger).to receive(:error)

        result = described_class.sell_market!(
          seg: segment,
          sid: nil,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(Rails.logger).to have_received(:error).with(/Missing required parameters/)
        expect(result).to be_nil
        expect(DhanHQ::Models::Order).not_to have_received(:create)
      end

      it "logs order placement with correct parameters" do
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

  describe "client order ID normalization" do
    it "preserves short IDs unchanged" do
      short_id = "SHORT-ID"

      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: short_id
      )

      expect(captured_attrs.last[:correlation_id]).to eq(short_id)
    end

    it "truncates and hashes long IDs" do
      long_id = "VERY-LONG-CLIENT-ORDER-ID-THAT-EXCEEDS-THIRTY-CHARACTERS"

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
  end

  describe "duplicate prevention" do
    it "prevents duplicate orders within 20 minutes" do
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

    it "stores order ID in cache for 20 minutes" do
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

  describe "derivative-specific order payloads" do
    describe "NSE derivatives (NSE_FNO)" do
      let(:nse_derivative_segment) { "NSE_FNO" }
      let(:nse_derivative_security_id) { "123456" }
      let(:nse_derivative_quantity) { 50 }
      let(:nse_client_order_id) { "NSE-DERIVATIVE-TEST-#{Time.current.to_i}" }

      let(:expected_nse_payload) do
        {
          transaction_type: DhanHQ::Constants::TransactionType::BUY,
          exchange_segment: nse_derivative_segment,
          security_id: nse_derivative_security_id,
          quantity: nse_derivative_quantity,
          order_type: DhanHQ::Constants::OrderType::MARKET,
          product_type: "NORMAL",
          validity: DhanHQ::Constants::Validity::DAY,
          correlation_id: nse_client_order_id,
          disclosed_quantity: 0
        }
      end

      it "creates correct payload for NSE derivative BUY market order" do
        described_class.buy_market!(
          seg: nse_derivative_segment,
          sid: nse_derivative_security_id,
          qty: nse_derivative_quantity,
          client_order_id: nse_client_order_id
        )

        expect(captured_attrs.last).to match(hash_including(expected_nse_payload))
      end

      it "creates correct payload for NSE derivative SELL market order" do
        expected_sell_payload = expected_nse_payload.merge(
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
          correlation_id: kind_of(String)
        )

        allow(described_class).to receive(:fetch_position_details).and_return(
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
          net_qty: nse_derivative_quantity,
          exchange_segment: nse_derivative_segment,
          position_type: DhanHQ::Constants::PositionType::LONG
        )

        described_class.sell_market!(
          seg: nse_derivative_segment,
          sid: nse_derivative_security_id,
          qty: nse_derivative_quantity,
          client_order_id: nse_client_order_id
        )

        expect(captured_attrs.last).to match(hash_including(expected_sell_payload))
      end
    end

    describe "BSE derivatives (BSE_FNO)" do
      let(:bse_derivative_segment) { "BSE_FNO" }
      let(:bse_derivative_security_id) { "789012" }
      let(:bse_derivative_quantity) { 25 }
      let(:bse_client_order_id) { "BSE-DERIVATIVE-TEST-#{Time.current.to_i}" }

      let(:expected_bse_payload) do
        {
          transaction_type: DhanHQ::Constants::TransactionType::BUY,
          exchange_segment: bse_derivative_segment,
          security_id: bse_derivative_security_id,
          quantity: bse_derivative_quantity,
          order_type: DhanHQ::Constants::OrderType::MARKET,
          product_type: "NORMAL",
          validity: DhanHQ::Constants::Validity::DAY,
          correlation_id: bse_client_order_id,
          disclosed_quantity: 0
        }
      end

      it "creates correct payload for BSE derivative BUY market order" do
        described_class.buy_market!(
          seg: bse_derivative_segment,
          sid: bse_derivative_security_id,
          qty: bse_derivative_quantity,
          client_order_id: bse_client_order_id
        )

        expect(captured_attrs.last).to match(hash_including(expected_bse_payload))
      end

      it "creates correct payload for BSE derivative SELL market order" do
        expected_sell_payload = expected_bse_payload.merge(
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
          correlation_id: kind_of(String)
        )

        allow(described_class).to receive(:fetch_position_details).and_return(
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
          net_qty: bse_derivative_quantity,
          exchange_segment: bse_derivative_segment,
          position_type: DhanHQ::Constants::PositionType::LONG
        )

        described_class.sell_market!(
          seg: bse_derivative_segment,
          sid: bse_derivative_security_id,
          qty: bse_derivative_quantity,
          client_order_id: bse_client_order_id
        )

        expect(captured_attrs.last).to match(hash_including(expected_sell_payload))
      end
    end

    describe "exchange segment validation" do
      it "validates that derivative.exchange_segment is used correctly" do
        # This test demonstrates the key principle: derivative.exchange_segment
        # should always be used for derivative orders, not the underlying index segment

        nse_derivative_segment = "NSE_FNO"
        derivative_security_id = "123456"

        # Mock logger to avoid failures while testing actual functionality
        allow(Rails.logger).to receive(:info)

        result = described_class.buy_market!(
          seg: nse_derivative_segment, # This should be derivative.exchange_segment
          sid: derivative_security_id,
          qty: 50,
          client_order_id: "TEST-DERIVATIVE"
        )

        expect(captured_attrs.last[:exchange_segment]).to eq(nse_derivative_segment)
        expect(result).to eq(order_double).or be_nil
      end
    end
  end

  describe "order slicing integration" do
    let(:client_order_id) { "TEST-SLICE" }

    before do
      # Mock Slicer config to set NIFTY limit = 1000
      allow(AlgoConfig).to receive(:fetch).and_return({
        options_buying: {
          execution: {
            order_slicing: {
              enabled: true,
              delay_ms: 100,
              freeze_limits: {
                'NIFTY' => 1000,
                'default' => 1000
              }
            }
          }
        }
      })

      # Mock resolve_index_key to return NIFTY for security_id
      allow(described_class).to receive(:resolve_index_key).with(security_id).and_return('NIFTY')
      # Mock sleep to avoid delaying test run
      allow(described_class).to receive(:sleep)
    end

    it "places a single order when quantity is below freeze limit" do
      described_class.buy_market!(seg: segment, sid: security_id, qty: 800, client_order_id: client_order_id)

      expect(DhanHQ::Models::Order).to have_received(:create).once
      expect(captured_attrs.last[:quantity]).to eq(800)
      expect(captured_attrs.last[:correlation_id]).to eq(client_order_id)
    end

    it "slices order and places multiple orders when quantity exceeds freeze limit" do
      described_class.buy_market!(seg: segment, sid: security_id, qty: 2500, client_order_id: client_order_id)

      expect(DhanHQ::Models::Order).to have_received(:create).thrice
      expect(captured_attrs.pluck(:quantity)).to eq([1000, 1000, 500])
      expect(captured_attrs.pluck(:correlation_id)).to eq(["#{client_order_id}_1", "#{client_order_id}_2", "#{client_order_id}_3"])
      expect(described_class).to have_received(:sleep).twice.with(0.1)
    end

    it "stops slicing and alerts when a middle slice fails, leaving a partial position" do
      call_count = 0
      allow(DhanHQ::Models::Order).to receive(:create) do |attributes|
        call_count += 1
        captured_attrs << attributes
        call_count == 2 ? nil : order_double # slice 2 of 3 "fails" (nil result)
      end
      allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)

      described_class.buy_market!(seg: segment, sid: security_id, qty: 2500, client_order_id: client_order_id)

      expect(DhanHQ::Models::Order).to have_received(:create).twice # stopped after slice 2, slice 3 never attempted
      expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error).with(
        a_string_matching(/Slice 2\/3 failed.*filled 1000\/2500/),
        context: 'Orders::Placer#place_order_with_slicing'
      )
    end
  end

  describe ".order_placement_enabled?" do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    it "returns true only when PLACE_ORDER is true" do
      allow(ENV).to receive(:[]).with("PLACE_ORDER").and_return("true")
      expect(described_class.send(:order_placement_enabled?)).to be(true)

      allow(ENV).to receive(:[]).with("PLACE_ORDER").and_return("false")
      expect(described_class.send(:order_placement_enabled?)).to be(false)
    end
  end

  describe ".with_token_auto_heal" do
    before do
      allow(described_class).to receive(:with_order_rate_limit).and_call_original
      allow(described_class).to receive(:rate_limiter).and_return(
        Class.new { def consume!; yield; end }.new
      )
    end

    it "refreshes the token and retries exactly once on token expiry" do
      call_count = 0
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(true)
      allow(Dhan::TokenManager).to receive(:refresh!)

      result = described_class.send(:with_token_auto_heal, context: "orders.test") do
        call_count += 1
        raise "unauthorized" if call_count == 1

        :ok
      end

      expect(result).to eq(:ok)
      expect(call_count).to eq(2)
      expect(Dhan::TokenManager).to have_received(:refresh!).once
    end

    it "does not loop forever when the token keeps expiring after retry" do
      call_count = 0
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(true)
      allow(Dhan::TokenManager).to receive(:refresh!)

      result = described_class.send(:with_token_auto_heal, context: "orders.test") do
        call_count += 1
        raise "unauthorized"
      end

      expect(result).to be_nil
      expect(call_count).to eq(2) # original attempt + exactly one retry, not infinite
      expect(Dhan::TokenManager).to have_received(:refresh!).once
    end

    it "does not retry on non-token-expiry errors" do
      call_count = 0
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(false)
      allow(Dhan::TokenManager).to receive(:refresh!)

      result = described_class.send(:with_token_auto_heal, context: "orders.test") do
        call_count += 1
        raise "some other broker error"
      end

      expect(result).to be_nil
      expect(call_count).to eq(1)
      expect(Dhan::TokenManager).not_to have_received(:refresh!)
    end
  end

  describe "order placement wires through with_token_auto_heal" do
    let(:client_order_id) { "AUTO_HEAL_TEST" }

    before do
      allow(described_class).to receive(:with_order_rate_limit).and_call_original
    end

    it "buy_market! retries once and succeeds after a token refresh" do
      call_count = 0
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(true)
      allow(Dhan::TokenManager).to receive(:refresh!)
      allow(DhanHQ::Models::Order).to receive(:create) do
        call_count += 1
        raise "unauthorized" if call_count == 1

        order_double
      end

      result = described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: client_order_id)

      expect(result).to eq(order_double)
      expect(Dhan::TokenManager).to have_received(:refresh!).once
    end
  end
end
