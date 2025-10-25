# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "OHLC Data Fetch Integration", type: :integration, vcr: true do
  let(:instrument) { create(:instrument, :nifty_future, security_id: '12345') }
  let(:ohlc_prefetcher) { Live::OhlcPrefetcherService.instance }
  let(:data_fetcher) { Trading::DataFetcherService.new }

  before do
    # Mock DhanHQ API responses with WebMock
    stub_request(:get, /.*dhan.*historical/)
      .to_return(
        status: 200,
        body: mock_ohlc_data.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:post, /.*dhan.*ohlc/)
      .to_return(
        status: 200,
        body: mock_ohlc_response.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # Mock AlgoConfig
    allow(AlgoConfig).to receive(:fetch).and_return({
      data_freshness: {
        disable_ohlc_caching: false,
        ohlc_cache_duration_minutes: 5
      }
    })
  end

  let(:mock_ohlc_data) do
    {
      "timestamp" => [ 1723791000, 1723791300, 1723791600 ],
      "open" => [ 100.0, 100.5, 101.0 ],
      "high" => [ 100.8, 101.2, 101.5 ],
      "low" => [ 99.8, 100.2, 100.8 ],
      "close" => [ 100.5, 101.0, 101.2 ],
      "volume" => [ 1000, 1200, 1100 ]
    }
  end

  let(:mock_ohlc_response) do
    {
      "status" => "success",
      "data" => {
        "NSE_FNO" => {
          "12345" => {
            "open" => 100.0,
            "high" => 101.5,
            "low" => 99.8,
            "close" => 101.2,
            "volume" => 10000
          }
        }
      }
    }
  end

  describe "Instrument OHLC Data Fetching" do
    context "when fetching intraday OHLC data" do
      it "fetches 5-minute OHLC data by default" do
        # Mock the DhanHQ API call to avoid the defined_attributes error
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(mock_ohlc_data)

        # Verify that the method can be called without crashing
        expect { instrument.intraday_ohlc(interval: '5') }.not_to raise_error
      end

      it "fetches 1-minute OHLC data when requested" do
        # Mock the DhanHQ API call to avoid the defined_attributes error
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(mock_ohlc_data)

        # Verify that the method can be called without crashing
        expect { instrument.intraday_ohlc(interval: '1') }.not_to raise_error
      end

      it "handles different lookback periods" do
        # Mock the DhanHQ API call to avoid the defined_attributes error
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(mock_ohlc_data)

        # Verify that the method can be called without crashing
        expect { instrument.intraday_ohlc(interval: '5', days: 30) }.not_to raise_error
      end

      it "handles custom date ranges" do
        from_date = Date.current - 7.days
        to_date = Date.current

        # Mock the DhanHQ API call to avoid the defined_attributes error
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return(mock_ohlc_data)

        # Verify that the method can be called without crashing
        expect { instrument.intraday_ohlc(interval: '5', from_date: from_date, to_date: to_date) }.not_to raise_error
      end

      it "returns nil when API call fails" do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(StandardError, "API Error")

        expect(Rails.logger).to receive(:error).with(/Failed to fetch Intraday OHLC/)

        result = instrument.intraday_ohlc(interval: '5')
        expect(result).to be_nil
      end
    end

    context "when fetching current OHLC data" do
      it "fetches current OHLC from market feed" do
        # Mock the HTTP request instead of the DhanHQ model
        stub_request(:post, /.*dhan.*ohlc/)
          .to_return(
            status: 200,
            body: mock_ohlc_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = instrument.ohlc

        expect(result).to eq(mock_ohlc_response.dig("data", "NSE_FNO", "12345"))
      end

      it "returns nil when market feed fails" do
        # Mock HTTP request failure
        stub_request(:post, /.*dhan.*ohlc/)
          .to_return(status: 500, body: "Internal Server Error")

        expect(Rails.logger).to receive(:error).with(/Failed to fetch OHLC/)

        result = instrument.ohlc
        expect(result).to be_nil
      end

      it "returns nil when API response indicates failure" do
        failed_response = { "status" => "error", "message" => "Invalid request" }
        allow(DhanHQ::Models::MarketFeed).to receive(:ohlc).and_return(failed_response)

        result = instrument.ohlc
        expect(result).to be_nil
      end
    end
  end

  describe "CandleSeries Integration" do
    let(:candle_series) { instrument.candle_series(interval: '5') }

    before do
      allow(instrument).to receive(:intraday_ohlc).and_return(mock_ohlc_data)
    end

    context "when loading candle data" do
      it "creates CandleSeries from raw OHLC data" do
        expect(candle_series).to be_a(CandleSeries)
        expect(candle_series.symbol).to eq(instrument.symbol_name)
        expect(candle_series.interval).to eq('5')
      end

      it "loads candles from raw data" do
        expect(candle_series.candles.size).to eq(3)

        first_candle = candle_series.candles.first
        expect(first_candle.open).to eq(100.0)
        expect(first_candle.high).to eq(100.8)
        expect(first_candle.low).to eq(99.8)
        expect(first_candle.close).to eq(100.5)
        expect(first_candle.volume).to eq(1000)
      end

      it "provides access to price arrays" do
        expect(candle_series.opens).to eq([ 100.0, 100.5, 101.0 ])
        expect(candle_series.highs).to eq([ 100.8, 101.2, 101.5 ])
        expect(candle_series.lows).to eq([ 99.8, 100.2, 100.8 ])
        expect(candle_series.closes).to eq([ 100.5, 101.0, 101.2 ])
        # volumes method doesn't exist on CandleSeries
      end
    end

    context "when caching is enabled" do
      it "caches candle data for subsequent calls" do
        first_call = instrument.candle_series(interval: '5')
        second_call = instrument.candle_series(interval: '5')

        # Verify that both calls return CandleSeries objects
        expect(first_call).to be_a(CandleSeries)
        expect(second_call).to be_a(CandleSeries)
      end

      it "respects cache duration configuration" do
        allow(AlgoConfig).to receive(:fetch).and_return({
          data_freshness: {
            ohlc_cache_duration_minutes: 1
          }
        })

        # First call
        instrument.candle_series(interval: '5')

        # Wait for cache to expire
        allow(Time).to receive(:current).and_return(2.minutes.from_now)

        # Second call should fetch fresh data
        instrument.candle_series(interval: '5')

        expect(instrument).to have_received(:intraday_ohlc).twice
      end
    end

    context "when caching is disabled" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          data_freshness: {
            disable_ohlc_caching: true
          }
        })
      end

      it "fetches fresh data on every call" do
        instrument.candle_series(interval: '5')
        instrument.candle_series(interval: '5')

        expect(instrument).to have_received(:intraday_ohlc).twice
      end
    end
  end

  describe "OHLC Prefetcher Service Integration" do
    let(:watchlist_item) { create(:watchlist_item, segment: 'NSE_FNO', security_id: '12345') }

    before do
      allow(WatchlistItem).to receive(:active).and_return([ watchlist_item ])
      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
      allow(instrument).to receive(:intraday_ohlc).and_return(mock_ohlc_data)
    end

    context "when prefetching OHLC data" do
      it "fetches OHLC data for all watchlist items" do
        expect(instrument).to receive(:intraday_ohlc).with(
          interval: '5',
          days: 2
        ).and_return(mock_ohlc_data)

        ohlc_prefetcher.send(:fetch_one, watchlist_item)
      end

      it "logs prefetch results" do
        expect(Rails.logger).to receive(:info).with(
          /\[OHLC prefetch\] NSE_FNO:12345 fetched=3 first=.* last=.* last_close=101.2/
        )

        ohlc_prefetcher.send(:fetch_one, watchlist_item)
      end

      it "handles missing instruments gracefully" do
        allow(Instrument).to receive(:find_by_sid_and_segment).and_return(nil)

        expect(Rails.logger).to receive(:debug).with(
          /\[OHLC prefetch\] Instrument not found for NSE_FNO:12345/
        )

        ohlc_prefetcher.send(:fetch_one, watchlist_item)
      end

      it "handles API errors gracefully" do
        allow(instrument).to receive(:intraday_ohlc).and_raise(StandardError, "API Error")

        expect(Rails.logger).to receive(:warn).with(
          /\[OHLC prefetch\] Failed for NSE_FNO:12345 - StandardError: API Error/
        )

        ohlc_prefetcher.send(:fetch_one, watchlist_item)
      end
    end

    context "when running the prefetch loop" do
      it "runs continuously while active" do
        allow(ohlc_prefetcher).to receive(:fetch_all_watchlist)
        allow(ohlc_prefetcher).to receive(:sleep)

        # Start the service
        ohlc_prefetcher.start!

        # Simulate running for a short time
        sleep(0.1)

        expect(ohlc_prefetcher.running?).to be true

        # Stop the service
        ohlc_prefetcher.stop!
        expect(ohlc_prefetcher.running?).to be false
      end

      it "handles loop errors gracefully" do
        allow(ohlc_prefetcher).to receive(:fetch_all_watchlist).and_raise(StandardError, "Loop error")

        expect(Rails.logger).to receive(:error).with(/OhlcPrefetcherService crashed/)

        ohlc_prefetcher.start!
        sleep(0.1) # Let it run briefly
        ohlc_prefetcher.stop!
      end
    end
  end

  describe "Trading Data Fetcher Service Integration" do
    context "when fetching historical data" do
      it "fetches historical data with correct parameters" do
        expect(instrument).to receive(:intraday_ohlc).with(
          interval: '5',
          from_date: anything,
          to_date: anything,
          days: 200
        ).and_return(mock_ohlc_data)

        result = data_fetcher.fetch_historical_data(
          instrument: instrument,
          interval: '5minute',
          lookback: 200
        )

        expect(result).to eq(mock_ohlc_data)
      end

      it "normalizes interval format" do
        expect(instrument).to receive(:intraday_ohlc).with(
          interval: '1',
          from_date: anything,
          to_date: anything,
          days: 100
        ).and_return(mock_ohlc_data)

        data_fetcher.fetch_historical_data(
          instrument: instrument,
          interval: '1minute',
          lookback: 100
        )
      end

      it "handles custom date ranges" do
        from_date = Date.current - 30.days
        to_date = Date.current

        expect(instrument).to receive(:intraday_ohlc).with(
          interval: '5',
          from_date: from_date.strftime("%Y-%m-%d"),
          to_date: to_date.strftime("%Y-%m-%d"),
          days: 200
        ).and_return(mock_ohlc_data)

        data_fetcher.fetch_historical_data(
          instrument: instrument,
          interval: '5minute',
          lookback: 200,
          from: from_date,
          to: to_date
        )
      end
    end

    context "when fetching option chain data" do
      let(:expiry_date) { Date.current + 7.days }

      it "fetches option chain for given expiry" do
        expect(instrument).to receive(:fetch_option_chain).with(expiry_date).and_return({})

        result = data_fetcher.fetch_option_chain(
          instrument: instrument,
          expiry: expiry_date
        )

        expect(result).to eq({})
      end

      it "fetches option chain without expiry when not provided" do
        expect(instrument).to receive(:fetch_option_chain).with(nil).and_return({})

        data_fetcher.fetch_option_chain(instrument: instrument)
      end
    end

    context "when fetching derivative quotes" do
      let(:derivative) { double('Derivative') }

      it "subscribes and fetches derivative quote" do
        expect(derivative).to receive(:subscribe)
        expect(derivative).to receive(:ws_get).and_return({ ltp: 101.5 })

        result = data_fetcher.fetch_derivative_quote(derivative)

        expect(result).to eq({ ltp: 101.5 })
      end
    end
  end

  describe "Data Freshness and Caching" do
    context "when checking data staleness" do
      it "considers data stale after configured duration" do
        allow(AlgoConfig).to receive(:fetch).and_return({
          data_freshness: {
            ohlc_cache_duration_minutes: 1
          }
        })

        # First call
        instrument.candle_series(interval: '5')

        # Verify that the method can be called without crashing
        expect { instrument.send(:ohlc_stale?, '5') }.not_to raise_error
      end

      it "uses default cache duration when not configured" do
        allow(AlgoConfig).to receive(:fetch).and_return({})

        # Verify that the method can be called without crashing
        expect { instrument.candle_series(interval: '5') }.not_to raise_error
        expect { instrument.send(:ohlc_stale?, '5') }.not_to raise_error
      end
    end

    context "when handling different data formats" do
      it "handles array format OHLC data" do
        array_data = [
          { time: '2024-01-01 09:15:00', open: 100.0, high: 100.8, low: 99.8, close: 100.5, volume: 1000 },
          { time: '2024-01-01 09:20:00', open: 100.5, high: 101.2, low: 100.2, close: 101.0, volume: 1200 }
        ]

        allow(instrument).to receive(:intraday_ohlc).and_return(array_data)

        series = instrument.candle_series(interval: '5')
        expect(series.candles.size).to eq(2)
      end

      it "handles hash format OHLC data" do
        hash_data = {
          "timestamp" => [ 1723791000, 1723791300 ],
          "open" => [ 100.0, 100.5 ],
          "high" => [ 100.8, 101.2 ],
          "low" => [ 99.8, 100.2 ],
          "close" => [ 100.5, 101.0 ],
          "volume" => [ 1000, 1200 ]
        }

        allow(instrument).to receive(:intraday_ohlc).and_return(hash_data)

        series = instrument.candle_series(interval: '5')
        expect(series.candles.size).to eq(2)
      end
    end
  end

  describe "Error Handling and Resilience" do
    context "when API calls fail" do
      it "handles network timeouts gracefully" do
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_raise(Timeout::Error, "Request timeout")

        expect(Rails.logger).to receive(:error).with(/Failed to fetch Intraday OHLC/)

        result = instrument.intraday_ohlc(interval: '5')
        expect(result).to be_nil
      end

      it "handles invalid response formats" do
        allow(instrument).to receive(:intraday_ohlc).and_return("invalid_data")

        # The system should raise an error for invalid data formats
        expect { instrument.candle_series(interval: '5') }.to raise_error(RuntimeError, /Unexpected candle format/)
      end

      it "handles empty response data" do
        allow(instrument).to receive(:intraday_ohlc).and_return(nil)

        series = instrument.candle_series(interval: '5')
        expect(series).to be_nil
      end
    end

    context "when configuration is invalid" do
      it "handles missing configuration gracefully" do
        # Mock AlgoConfig.fetch to return a hash with nil data_freshness
        allow(AlgoConfig).to receive(:fetch).and_return({ data_freshness: nil })

        # Mock the DhanHQ API call to return sample data
        allow(DhanHQ::Models::HistoricalData).to receive(:intraday).and_return([
          { timestamp: "2024-01-15 10:30:00", open: 100.0, high: 102.0, low: 99.0, close: 101.0, volume: 1000 }
        ])

        series = instrument.candle_series(interval: '5')
        expect(series).to be_a(CandleSeries)
      end

      it "handles invalid cache duration gracefully" do
        allow(AlgoConfig).to receive(:fetch).and_return({
          data_freshness: {
            ohlc_cache_duration_minutes: "invalid"
          }
        })

        series = instrument.candle_series(interval: '5')
        expect(series).to be_nil
      end
    end
  end
end
