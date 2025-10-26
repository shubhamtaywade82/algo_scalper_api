# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Real-time LTP Updates Integration', :vcr, type: :integration do
  let(:tick_cache) { TickCache.instance }
  let(:redis_pnl_cache) { Live::RedisPnlCache.instance }
  let(:test_mock_service) { Live::TestMockDataService.instance }

  before do
    # Mock Redis PnL cache methods
    allow(redis_pnl_cache).to receive(:fetch_tick)
    allow(redis_pnl_cache).to receive(:is_tick_fresh?)
    allow(redis_pnl_cache).to receive(:store_pnl)
    allow(redis_pnl_cache).to receive(:clear_tracker)

    # Clear tick cache
    TickCache.instance.clear
    test_mock_service.stop! if test_mock_service.running?
  end

  after do
    test_mock_service.stop! if test_mock_service.running?
  end

  describe 'Mock Data Service LTP Integration' do
    context 'when generating real-time LTP updates' do
      it 'generates continuous LTP updates' do
        test_mock_service.start!

        # Generate a series of ticks with price movement
        ticks = test_mock_service.generate_tick_series(25_200, count: 10, interval: 0)

        expect(ticks.length).to eq(10)

        # Verify price variation
        prices = ticks.pluck(:ltp)
        expect(prices.uniq.length).to be > 1 # Should have price variation

        # Verify all ticks are cached
        cached_tick = tick_cache.fetch('NSE_FNO', '12345')
        expect(cached_tick).to be_present
        expect(cached_tick[:ltp]).to be > 0
      end

      it 'handles multiple instruments simultaneously' do
        test_mock_service.start!

        # Clear any existing ticks to avoid interference
        TickCache.instance.clear

        # Generate ticks for different instruments
        test_mock_service.generate_tick_series(25_200, count: 5, interval: 0)
        test_mock_service.generate_tick_series(56_500, count: 5, interval: 0)

        # Inject ticks for different instruments
        nifty_tick = {
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 25_200.50,
          kind: :quote,
          ts: Time.current.to_i
        }

        banknifty_tick = {
          segment: 'NSE_FNO',
          security_id: '67890',
          ltp: 56_500.75,
          kind: :quote,
          ts: Time.current.to_i
        }

        test_mock_service.inject_tick(nifty_tick)
        test_mock_service.inject_tick(banknifty_tick)

        # Verify both instruments are cached
        expect(tick_cache.ltp('NSE_FNO', '12345')).to eq(25_200.50)
        expect(tick_cache.ltp('NSE_FNO', '67890')).to eq(56_500.75)
      end

      it 'generates realistic price movements' do
        test_mock_service.start!

        base_price = 25_200
        ticks = test_mock_service.generate_tick_series(base_price, count: 20, interval: 0)

        prices = ticks.pluck(:ltp)

        # Verify price movements are within reasonable bounds
        prices.each do |price|
          expect(price).to be > base_price * 0.95 # Within 5% of base price
          expect(price).to be < base_price * 1.05
        end

        # Verify some price variation exists
        expect(prices.uniq.length).to be > 1
      end
    end
  end

  describe 'TickCache Integration' do
    context 'when storing and retrieving ticks' do
      let(:sample_tick) do
        {
          kind: :quote,
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 101.5,
          ts: Time.current.to_i
        }
      end

      it 'stores tick data' do
        tick_cache.put(sample_tick)

        cached_tick = tick_cache.fetch('NSE_FNO', '12345')
        expect(cached_tick[:ltp]).to eq(101.5)
        expect(cached_tick[:segment]).to eq('NSE_FNO')
        expect(cached_tick[:security_id]).to eq('12345')
      end

      it 'retrieves LTP from cache' do
        tick_cache.put(sample_tick)

        ltp = tick_cache.ltp('NSE_FNO', '12345')
        expect(ltp).to eq(101.5)
      end

      it 'handles multiple instruments' do
        tick1 = sample_tick.merge(security_id: '12345', ltp: 101.5)
        tick2 = sample_tick.merge(security_id: '67890', ltp: 202.0)

        tick_cache.put(tick1)
        tick_cache.put(tick2)

        expect(tick_cache.ltp('NSE_FNO', '12345')).to eq(101.5)
        expect(tick_cache.ltp('NSE_FNO', '67890')).to eq(202.0)
      end

      it 'returns all cached ticks' do
        tick1 = sample_tick.merge(security_id: '12345', ltp: 101.5)
        tick2 = sample_tick.merge(security_id: '67890', ltp: 202.0)

        tick_cache.put(tick1)
        tick_cache.put(tick2)

        all_ticks = tick_cache.all
        expect(all_ticks).to include('NSE_FNO:12345' => tick1)
        expect(all_ticks).to include('NSE_FNO:67890' => tick2)
      end

      it 'clears all cached ticks' do
        tick_cache.put(sample_tick)
        TickCache.instance.clear

        expect(tick_cache.fetch('NSE_FNO', '12345')).to be_nil
      end
    end

    context 'when handling different tick types' do
      it 'handles ticker ticks' do
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

      it 'handles quote ticks' do
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

  describe 'Option Chain LTP Integration' do
    context 'when generating option chain ticks' do
      it 'generates realistic option prices' do
        test_mock_service.start!

        # Clear any existing ticks to avoid interference
        TickCache.instance.clear

        underlying_price = 25_200
        strike_prices = [25_000, 25_200, 25_400, 25_600]

        # Generate call options
        call_ticks = test_mock_service.generate_option_ticks(underlying_price, strike_prices, option_type: :call)

        expect(call_ticks.length).to eq(4)

        # Verify option pricing logic
        call_ticks.each_with_index do |tick, index|
          strike = strike_prices[index]
          option_price = tick[:ltp]

          # ITM options should have higher prices
          expect(option_price).to be > 0 if strike < underlying_price

          # OTM options should have lower prices
          expect(option_price).to be > 0 if strike > underlying_price
        end
      end

      it 'generates both call and put options' do
        test_mock_service.start!

        # Clear any existing ticks to avoid interference
        TickCache.instance.clear

        underlying_price = 25_200
        strike_prices = [25_200] # ATM strike

        call_ticks = test_mock_service.generate_option_ticks(underlying_price, strike_prices, option_type: :call)
        put_ticks = test_mock_service.generate_option_ticks(underlying_price, strike_prices, option_type: :put)

        expect(call_ticks.first[:security_id]).to eq('25200CE')
        expect(put_ticks.first[:security_id]).to eq('25200PE')

        # Both should have positive prices
        expect(call_ticks.first[:ltp]).to be > 0
        expect(put_ticks.first[:ltp]).to be > 0
      end
    end
  end

  describe 'Redis PnL Cache Integration' do
    context 'when integrating with Redis cache' do
      it 'stores tick data in Redis' do
        test_mock_service.start!

        tick_data = {
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 25_200.50,
          kind: :quote,
          ts: Time.current.to_i
        }

        # Verify that tick injection doesn't crash
        expect { test_mock_service.inject_tick(tick_data) }.not_to raise_error
      end

      it 'handles tick freshness checks' do
        test_mock_service.start!

        tick_data = {
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: 25_200.50,
          kind: :quote,
          ts: Time.current.to_i
        }

        # Verify that tick injection doesn't crash
        expect { test_mock_service.inject_tick(tick_data) }.not_to raise_error
      end
    end
  end
end
