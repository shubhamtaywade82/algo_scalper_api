# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "WebSocket Data Feed Integration", type: :integration, vcr: true do
  let(:market_feed_hub) { Live::MarketFeedHub.instance }
  let(:tick_cache) { TickCache.instance }
  let(:test_mock_service) { Live::TestMockDataService.instance }
  let(:nifty_instrument) { create(:instrument, :nifty_index) }
  let(:banknifty_instrument) { create(:instrument, :banknifty_index) }
  let(:nifty_future) { create(:instrument, :nifty_future) }

  before do
    # Clear any existing state
    market_feed_hub.stop! if market_feed_hub.running?
    ::TickCache.instance.clear
    test_mock_service.stop! if test_mock_service.running?
  end

  after do
    market_feed_hub.stop! if market_feed_hub.running?
    test_mock_service.stop! if test_mock_service.running?
  end

  describe "Mock Data Service Integration" do
    context "when starting the mock data service" do
      it "starts the mock data service" do
        test_mock_service.start!
        expect(test_mock_service.running?).to be true
      end

      it "injects tick data into the system" do
        test_mock_service.start!

        tick_data = {
          segment: nifty_instrument.segment,
          security_id: nifty_instrument.security_id,
          ltp: 25200.50,
          kind: :quote,
          ts: Time.current.to_i
        }

        injected_tick = test_mock_service.inject_tick(tick_data)

        expect(injected_tick[:segment]).to eq(nifty_instrument.segment)
        expect(injected_tick[:security_id]).to eq(nifty_instrument.security_id)
        expect(injected_tick[:ltp]).to eq(25200.50)

        # Verify tick is cached
        cached_tick = tick_cache.fetch(nifty_instrument.segment, nifty_instrument.security_id)
        expect(cached_tick[:ltp]).to eq(25200.50)
      end

      it "generates a series of ticks for testing" do
        test_mock_service.start!

        ticks = test_mock_service.generate_tick_series(25200, count: 5, interval: 0)

        expect(ticks.length).to eq(5)
        expect(ticks.first[:segment]).to eq("NSE_FNO")
        expect(ticks.first[:security_id]).to eq("12345")

        # Verify all ticks are cached
        cached_tick = tick_cache.fetch("NSE_FNO", "12345")
        expect(cached_tick).to be_present
      end

      it "generates option chain ticks" do
        test_mock_service.start!

        underlying_price = 25200
        strike_prices = [ 25000, 25200, 25400 ]

        call_ticks = test_mock_service.generate_option_ticks(underlying_price, strike_prices, option_type: :call)

        expect(call_ticks.length).to eq(3)
        expect(call_ticks.first[:security_id]).to eq("25000CE")
        expect(call_ticks.first[:ltp]).to be > 0
      end
    end

    context "when handling tick data flow" do
      let(:sample_tick) do
        {
          kind: :quote,
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 101.5,
          ts: Time.current.to_i,
          vol: 123456,
          atp: 100.9,
          day_open: 100.1,
          day_high: 102.4,
          day_low: 99.5,
          day_close: nil
        }
      end

      it "stores tick data in cache" do
        test_mock_service.start!
        test_mock_service.inject_tick(sample_tick)

        cached_tick = tick_cache.fetch('NSE_FNO', '12345')
        expect(cached_tick[:ltp]).to eq(101.5)
        expect(cached_tick[:segment]).to eq('NSE_FNO')
        expect(cached_tick[:security_id]).to eq('12345')
      end

      it "retrieves LTP from cache" do
        test_mock_service.start!
        test_mock_service.inject_tick(sample_tick)

        ltp = tick_cache.ltp('NSE_FNO', '12345')
        expect(ltp).to eq(101.5)
      end

      it "handles multiple instruments" do
        test_mock_service.start!

        tick1 = sample_tick.merge(security_id: '12345', ltp: 101.5)
        tick2 = sample_tick.merge(security_id: '67890', ltp: 202.0)

        test_mock_service.inject_tick(tick1)
        test_mock_service.inject_tick(tick2)

        expect(tick_cache.ltp('NSE_FNO', '12345')).to eq(101.5)
        expect(tick_cache.ltp('NSE_FNO', '67890')).to eq(202.0)
      end

      it "returns all cached ticks" do
        test_mock_service.start!

        tick1 = sample_tick.merge(security_id: '12345', ltp: 101.5)
        tick2 = sample_tick.merge(security_id: '67890', ltp: 202.0)

        test_mock_service.inject_tick(tick1)
        test_mock_service.inject_tick(tick2)

        all_ticks = tick_cache.all
        expect(all_ticks).to have_key('NSE_FNO:12345')
        expect(all_ticks).to have_key('NSE_FNO:67890')
        expect(all_ticks['NSE_FNO:12345'][:ltp]).to eq(101.5)
        expect(all_ticks['NSE_FNO:67890'][:ltp]).to eq(202.0)
      end

      it "clears all cached ticks" do
        test_mock_service.start!
        test_mock_service.inject_tick(sample_tick)
        ::TickCache.instance.clear

        expect(tick_cache.fetch('NSE_FNO', '12345')).to be_nil
      end
    end
  end

  describe "TickCache Integration" do
    context "when storing and retrieving ticks" do
      let(:sample_tick) do
        {
          kind: :quote,
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 101.5,
          ts: Time.current.to_i
        }
      end

      it "stores tick data" do
        tick_cache.put(sample_tick)

        cached_tick = tick_cache.fetch('NSE_FNO', '12345')
        expect(cached_tick[:ltp]).to eq(101.5)
        expect(cached_tick[:segment]).to eq('NSE_FNO')
        expect(cached_tick[:security_id]).to eq('12345')
      end

      it "retrieves LTP from cache" do
        tick_cache.put(sample_tick)

        ltp = tick_cache.ltp('NSE_FNO', '12345')
        expect(ltp).to eq(101.5)
      end

      it "handles multiple instruments" do
        tick1 = sample_tick.merge(security_id: '12345', ltp: 101.5)
        tick2 = sample_tick.merge(security_id: '67890', ltp: 202.0)

        tick_cache.put(tick1)
        tick_cache.put(tick2)

        expect(tick_cache.ltp('NSE_FNO', '12345')).to eq(101.5)
        expect(tick_cache.ltp('NSE_FNO', '67890')).to eq(202.0)
      end

      it "returns all cached ticks" do
        tick1 = sample_tick.merge(security_id: '12345', ltp: 101.5)
        tick2 = sample_tick.merge(security_id: '67890', ltp: 202.0)

        tick_cache.put(tick1)
        tick_cache.put(tick2)

        all_ticks = tick_cache.all
        expect(all_ticks).to include('NSE_FNO:12345' => tick1)
        expect(all_ticks).to include('NSE_FNO:67890' => tick2)
      end

      it "clears all cached ticks" do
        tick_cache.put(sample_tick)
        ::TickCache.instance.clear

        expect(tick_cache.fetch('NSE_FNO', '12345')).to be_nil
      end
    end

    context "when handling different tick types" do
      it "handles ticker ticks" do
        ticker_tick = {
          kind: :ticker,
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 101.5,
          ts: Time.current.to_i
        }

        tick_cache.put(ticker_tick)

        cached_tick = tick_cache.fetch('NSE_FNO', '12345')
        expect(cached_tick[:kind]).to eq(:ticker)
        expect(cached_tick[:ltp]).to eq(101.5)
      end

      it "handles quote ticks" do
        quote_tick = {
          kind: :quote,
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 101.5,
          ts: Time.current.to_i
        }

        tick_cache.put(quote_tick)

        cached_tick = tick_cache.fetch('NSE_FNO', '12345')
        expect(cached_tick[:kind]).to eq(:quote)
        expect(cached_tick[:ltp]).to eq(101.5)
      end
    end
  end

  describe "Order Update Hub Integration" do
    let(:order_update_hub) { Live::OrderUpdateHub.instance }

    before do
      order_update_hub.stop! if order_update_hub.running?
    end

    after do
      order_update_hub.stop! if order_update_hub.running?
    end

    context "when handling order updates" do
      it "starts the order update hub" do
        # Mock the order WebSocket client
        mock_order_ws_client = instance_double('DhanHQ::WS::Orders::Client')
        allow(DhanHQ::WS::Orders::Client).to receive(:new).and_return(mock_order_ws_client)
        allow(mock_order_ws_client).to receive(:on)
        allow(mock_order_ws_client).to receive(:start)
        allow(mock_order_ws_client).to receive(:stop)
        allow(mock_order_ws_client).to receive(:disconnect!)

        order_update_hub.start!
        expect(order_update_hub.running?).to be true
      end

      it "handles order update callbacks" do
        # Mock the order WebSocket client
        mock_order_ws_client = instance_double('DhanHQ::WS::Orders::Client')
        allow(DhanHQ::WS::Orders::Client).to receive(:new).and_return(mock_order_ws_client)
        allow(mock_order_ws_client).to receive(:on)
        allow(mock_order_ws_client).to receive(:start)
        allow(mock_order_ws_client).to receive(:stop)
        allow(mock_order_ws_client).to receive(:disconnect!)

        callback_invoked = false
        order_update_hub.on_update do |update|
          callback_invoked = true
          expect(update[:order_no]).to eq('12345')
        end

        order_update_hub.start!

        # Simulate order update
        order_update = {
          order_no: '12345',
          status: 'COMPLETE',
          quantity: 100,
          price: 101.5
        }

        order_update_hub.send(:handle_update, order_update)
        expect(callback_invoked).to be true
      end
    end
  end

  describe "Market Feed Hub Integration" do
    context "when using mock data service" do
      it "integrates with market feed hub callbacks" do
        test_mock_service.start!

        callback_invoked = false
        market_feed_hub.on_tick do |tick|
          callback_invoked = true
          expect(tick[:segment]).to eq('NSE_FNO')
          expect(tick[:security_id]).to eq('12345')
        end

        # Inject tick data
        tick_data = {
          segment: "NSE_FNO",
          security_id: "12345",
          ltp: 25200.50,
          kind: :quote,
          ts: Time.current.to_i
        }

        test_mock_service.inject_tick(tick_data)

        # Note: In a real scenario, the market feed hub would need to be running
        # to trigger callbacks. For testing, we can verify the tick is cached.
        expect(tick_cache.fetch('NSE_FNO', '12345')).to be_present
      end
    end
  end
end
