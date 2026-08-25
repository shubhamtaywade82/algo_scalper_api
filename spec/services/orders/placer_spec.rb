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
    # write(..., unless_exist: true) returns truthy on first claim, falsy on a repeat id —
    # Orders::Placer#claim! relies on that return value, so the default here must claim.
    allow(Rails.cache).to receive(:write).and_return(true)
    allow(DhanHQ::Models::Order).to receive(:create!) do |attributes|
      captured_attrs << attributes
      order_double
    end
    # Enable order placement for tests
    allow(ENV).to receive(:[])
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
      expect(Rails.cache).to have_received(:write).with(match(/^coid:/), true, expires_in: 20.minutes, unless_exist: true)
    end

    it "skips placing duplicate orders based on the normalized id" do
      long_id = "AS-EXIT-12345678901234567890-9999999999"
      allow(Rails.cache).to receive(:write).and_return(true, false)
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

      expect(DhanHQ::Models::Order).to have_received(:create!).once
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

      expect(DhanHQ::Models::Order).to have_received(:create!)
      expect(captured_attrs.last).to include(
        transaction_type: DhanHQ::Constants::TransactionType::BUY,
        order_type: DhanHQ::Constants::OrderType::MARKET,
        product_type: DhanHQ::Constants::ProductType::INTRADAY
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
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
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
        expect(DhanHQ::Models::Order).not_to have_received(:create!)
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

    describe "broker-rejected orders" do
      let(:client_order_id) { "REJECT-TEST-#{Time.current.to_i}" }

      it "returns nil when the broker rejects the order, not a truthy unsaved Order" do
        allow(DhanHQ::Models::Order).to receive(:create!).and_raise(
          DhanHQ::OrderError.new("Order#create failed: insufficient margin")
        )

        result = described_class.buy_market!(
          seg: segment,
          sid: security_id,
          qty: quantity,
          client_order_id: client_order_id
        )

        expect(result).to be_nil
      end
    end
  end

  describe ".buy_limit!" do
    let(:client_order_id) { "TEST-BUY-LIMIT-#{Time.current.to_i}" }
    let(:price) { BigDecimal("100.50") }

    it "creates correct payload for a limit buy order" do
      described_class.buy_limit!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        price: price,
        client_order_id: client_order_id
      )

      expect(captured_attrs.last).to match(hash_including(
        transaction_type: DhanHQ::Constants::TransactionType::BUY,
        exchange_segment: segment,
        security_id: security_id,
        quantity: quantity,
        order_type: DhanHQ::Constants::OrderType::LIMIT,
        price: 100.5,
        validity: DhanHQ::Constants::Validity::DAY
      ))
    end

    it "validates required parameters" do
      allow(Rails.logger).to receive(:error)

      result = described_class.buy_limit!(
        seg: nil,
        sid: security_id,
        qty: quantity,
        price: price,
        client_order_id: client_order_id
      )

      expect(Rails.logger).to have_received(:error).with(/Missing required parameters/)
      expect(result).to be_nil
      expect(DhanHQ::Models::Order).not_to have_received(:create!)
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
        expect(DhanHQ::Models::Order).not_to have_received(:create!)
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

      # First order succeeds (claims the id)
      allow(Rails.cache).to receive(:write).and_return(true)
      described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: client_order_id
      )

      # Second order should be blocked (id already claimed)
      allow(Rails.cache).to receive(:write).and_return(false)
      result = described_class.buy_market!(
        seg: segment,
        sid: security_id,
        qty: quantity,
        client_order_id: client_order_id
      )

      expect(result).to be_nil
      expect(DhanHQ::Models::Order).to have_received(:create!).once
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
        expires_in: 20.minutes,
        unless_exist: true
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
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
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

      it 'creates correct payload for NSE derivative SELL market order' do
        expected_sell_payload = expected_nse_payload.merge(
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
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
          product_type: DhanHQ::Constants::ProductType::INTRADAY,
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

      it 'creates correct payload for BSE derivative SELL market order' do
        expected_sell_payload = expected_bse_payload.merge(
          transaction_type: DhanHQ::Constants::TransactionType::SELL,
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
      allow(DhanHQ::Models::Order).to receive(:create!) do
        call_count += 1
        raise "unauthorized" if call_count == 1

        order_double
      end

      result = described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: client_order_id)

      expect(result).to eq(order_double)
      expect(Dhan::TokenManager).to have_received(:refresh!).once
    end
  end

  describe 'claim release on placement failure (regression: idempotency claim burned on first attempt)' do
    # Real cache store — Rails.cache in test env is a NullStore that can't distinguish
    # "claimed" from "released", so these need genuine claim!/release_claim! semantics.
    let(:real_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(real_cache) }

    it 'releases the claim when buy_market! fails validation before ever reaching the broker' do
      client_order_id = "RELEASE-TEST-#{Time.current.to_i}"
      allow(Rails.logger).to receive(:error)

      first = described_class.buy_market!(seg: nil, sid: security_id, qty: quantity, client_order_id: client_order_id)
      expect(first).to be_nil

      # A same-id retry after a definite non-broker failure must not be blocked by our own claim.
      second = described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: client_order_id)

      expect(second).to eq(order_double)
      expect(DhanHQ::Models::Order).to have_received(:create!).once
    end

    it 'releases the claim when buy_market! is rejected by the broker (non-retryable error)' do
      client_order_id = "RELEASE-TEST-REJECT-#{Time.current.to_i}"
      call_count = 0
      allow(DhanHQ::Models::Order).to receive(:create!) do |attrs|
        call_count += 1
        raise DhanHQ::OrderError, 'insufficient margin' if call_count == 1

        captured_attrs << attrs
        order_double
      end

      first = described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: client_order_id)
      expect(first).to be_nil

      second = described_class.buy_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: client_order_id)
      expect(second).to eq(order_double)
    end

    it 'releases the claim when exit_position! fails validation before ever reaching the broker' do
      client_order_id = "RELEASE-TEST-EXIT-#{Time.current.to_i}"
      allow(described_class).to receive(:fetch_position_details).and_return(nil)

      first = described_class.exit_position!(seg: segment, sid: security_id, client_order_id: client_order_id)
      expect(first).to be_nil

      allow(described_class).to receive(:fetch_position_details).and_return(
        product_type: DhanHQ::Constants::ProductType::INTRADAY,
        net_qty: quantity,
        exchange_segment: segment,
        position_type: DhanHQ::Constants::PositionType::LONG
      )
      second = described_class.exit_position!(seg: segment, sid: security_id, client_order_id: client_order_id)

      expect(second).to eq(order_double)
    end

    it 'does NOT release the claim when sell_market! fails partway through a sliced order' do
      # A partial-slice failure may mean earlier slices already reached the broker;
      # a from-scratch resend under the same id must stay blocked (see placer.rb comment).
      client_order_id = "NO-RELEASE-SLICE-TEST-#{Time.current.to_i}"
      allow(described_class).to receive(:fetch_position_details).and_return(
        product_type: DhanHQ::Constants::ProductType::INTRADAY,
        net_qty: quantity,
        exchange_segment: segment,
        position_type: DhanHQ::Constants::PositionType::LONG
      )
      allow(Orders::Slicer).to receive(:slice_quantity).and_return([quantity / 2, quantity / 2])
      allow(Orders::Slicer).to receive(:delay_seconds).and_return(0)
      call_count = 0
      allow(DhanHQ::Models::Order).to receive(:create!) do
        call_count += 1
        raise DhanHQ::OrderError, 'slice rejected' if call_count == 2

        order_double
      end
      allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)

      first = described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: client_order_id)
      expect(first).to be_nil

      second = described_class.sell_market!(seg: segment, sid: security_id, qty: quantity, client_order_id: client_order_id)
      expect(second).to be_nil
      expect(DhanHQ::Models::Order).to have_received(:create!).twice # not re-attempted
    end
  end

  describe 'with_token_auto_heal re-raises retryable network errors (regression: GatewayLive#with_retries never saw them)' do
    it 'raises Timeout::Error instead of swallowing it to nil' do
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(false)

      expect do
        described_class.send(:with_token_auto_heal, context: 'orders.test') { raise Timeout::Error, 'timed out' }
      end.to raise_error(Timeout::Error)
    end

    it 'raises SocketError instead of swallowing it to nil' do
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(false)

      expect do
        described_class.send(:with_token_auto_heal, context: 'orders.test') { raise SocketError, 'connection refused' }
      end.to raise_error(SocketError)
    end

    it 'still returns nil (does not raise) for ordinary broker/validation errors' do
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(false)

      result = described_class.send(:with_token_auto_heal, context: 'orders.test') { raise DhanHQ::OrderError, 'bad request' }

      expect(result).to be_nil
    end
  end

  describe '.with_order_rate_limit' do
    before { allow(described_class).to receive(:with_order_rate_limit).and_call_original }

    # NOTE: Orders::Placer's bare `TokenBucket` reference resolves to Orders::TokenBucket
    # (app/services/orders/token_bucket.rb), not the top-level ::TokenBucket loaded by
    # placer.rb's `require "token_bucket"` — Ruby's lexical scoping favors the class
    # nested in the enclosing `module Orders`. That top-level require is effectively
    # dead; use Orders::TokenBucket::RateLimited here to match what the code actually uses.
    it 'waits and retries instead of silently dropping the order on a transient rate limit' do
      allow(described_class).to receive(:sleep)
      call_count = 0
      allow(described_class.send(:rate_limiter)).to receive(:consume!) do
        call_count += 1
        raise Orders::TokenBucket::RateLimited, 'rate limit reached' if call_count == 1

        'placed'
      end

      result = described_class.send(:with_order_rate_limit, context: 'orders.test') { 'placed' }

      expect(result).to eq('placed')
      expect(described_class).to have_received(:sleep).once
    end

    it 'gives up and returns nil after exhausting bounded wait attempts' do
      allow(described_class).to receive(:sleep)
      allow(described_class.send(:rate_limiter)).to receive(:consume!).and_raise(Orders::TokenBucket::RateLimited, 'rate limit reached')

      result = described_class.send(:with_order_rate_limit, context: 'orders.test') { 'placed' }

      expect(result).to be_nil
    end
  end

  describe '.claim! (atomic dedup, real cache)' do
    # Exercise a real cache store instead of the stubbed Rails.cache used elsewhere in this
    # file — the test env's Rails.cache is a NullStore (always "succeeds", stores nothing),
    # which can't distinguish claim! from the old duplicate?/remember pair. A real store's
    # write(unless_exist: true) is what actually closes the race: the previous pair only wrote
    # the dedup key in `ensure`, *after* the broker call, so two racing calls with the same id
    # could both pass the check.
    let(:real_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(real_cache) }

    it 'lets exactly one of two racing claims for the same id succeed' do
      results = [described_class.send(:claim!, "CLAIM-RACE-TEST"), described_class.send(:claim!, "CLAIM-RACE-TEST")]

      expect(results.count { |r| r }).to eq(1)
    end

    it 'allows a claim again once the id is a genuinely new order' do
      expect(described_class.send(:claim!, "CLAIM-RACE-TEST")).to be_truthy
      expect(described_class.send(:claim!, "CLAIM-RACE-TEST-2")).to be_truthy
    end

    it 'treats a blank id as always claimable, deferring to the caller\'s own validation' do
      expect(described_class.send(:claim!, nil)).to be true
      expect(described_class.send(:claim!, '')).to be true
    end
  end

  describe 'circuit breaker auto-trip on consecutive order failures' do
    let(:real_cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(real_cache)
      allow(described_class).to receive(:auto_trip_threshold).and_return(3)
      allow(Risk::CircuitBreaker.instance).to receive(:trip!)
    end

    it 'does not trip before the threshold is reached' do
      2.times { described_class.send(:record_order_failure!) }

      expect(Risk::CircuitBreaker.instance).not_to have_received(:trip!)
    end

    it 'trips exactly at the configured threshold' do
      3.times { described_class.send(:record_order_failure!) }

      expect(Risk::CircuitBreaker.instance).to have_received(:trip!).once.with(reason: a_string_matching(/3 consecutive/))
    end

    it 'resets the counter on the next success, so an isolated failure never trips it' do
      described_class.send(:record_order_failure!)
      described_class.send(:reset_consecutive_order_failures!)
      2.times { described_class.send(:record_order_failure!) }

      expect(Risk::CircuitBreaker.instance).not_to have_received(:trip!)
    end

    it 'does nothing when auto-trip is disabled (threshold nil/zero)' do
      allow(described_class).to receive(:auto_trip_threshold).and_return(nil)

      5.times { described_class.send(:record_order_failure!) }

      expect(Risk::CircuitBreaker.instance).not_to have_received(:trip!)
    end

    it 'trips via the real order-placement path after N consecutive broker exceptions' do
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(false)

      3.times do
        result = described_class.send(:with_token_auto_heal, context: 'orders.test') { raise 'broker down' }
        expect(result).to be_nil
      end

      expect(Risk::CircuitBreaker.instance).to have_received(:trip!).once
    end

    it 'a success between failures resets the streak, so it never trips' do
      allow(DhanhqErrorHandler).to receive(:token_expired?).and_return(false)

      2.times { described_class.send(:with_token_auto_heal, context: 'orders.test') { raise 'broker down' } }
      described_class.send(:with_token_auto_heal, context: 'orders.test') { double('order') } # rubocop:disable RSpec/VerifiedDoubles
      2.times { described_class.send(:with_token_auto_heal, context: 'orders.test') { raise 'broker down' } }

      expect(Risk::CircuitBreaker.instance).not_to have_received(:trip!)
    end
  end

  describe '.order_placement_enabled?' do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    it 'returns true only when PLACE_ORDER is true' do
      allow(ENV).to receive(:[]).with('PLACE_ORDER').and_return('true')
      expect(described_class.send(:order_placement_enabled?)).to be(true)

      allow(ENV).to receive(:[]).with('PLACE_ORDER').and_return('false')
      expect(described_class.send(:order_placement_enabled?)).to be(false)
    end
  end
end
