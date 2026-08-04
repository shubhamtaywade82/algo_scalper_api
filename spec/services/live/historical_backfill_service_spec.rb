# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::HistoricalBackfillService do
  subject(:service) { described_class.new }

  let(:instrument) do
    build_stubbed(:instrument, security_id: '52175', symbol_name: 'NIFTY24500CE')
  end

  let(:redis_double) { instance_double(Redis) }

  # Raw response as returned by DhanHQ's intraday candle endpoint (hash-of-arrays format)
  let(:raw_candle_response) do
    {
      'open' => [100.0, 102.0],
      'high' => [105.0, 107.0],
      'low' => [98.0, 101.0],
      'close' => [103.0, 106.0],
      'volume' => [1000, 1200],
      'timestamp' => [Time.zone.parse('2026-06-19 09:15:00').to_i,
                      Time.zone.parse('2026-06-19 09:16:00').to_i]
    }
  end

  before do
    allow(service).to receive(:redis).and_return(redis_double)

    # Circuit breaker / rate limiter stubs
    allow(redis_double).to receive(:exists?).with(described_class::CIRCUIT_OPEN_KEY).and_return(false)
    allow(redis_double).to receive(:get).with(described_class::RATE_TS_KEY).and_return(nil)
    allow(redis_double).to receive(:get).with(described_class::FAILURE_CTR_KEY).and_return('0')
    allow(redis_double).to receive(:set)
    allow(redis_double).to receive(:del)
    allow(redis_double).to receive(:incr).and_return(1)
    allow(redis_double).to receive(:expire)

    # StateStore redis mock
    allow(OptionsBuying::StateStore).to receive(:minute_ticks).and_return([])
    allow(OptionsBuying::StateStore).to receive(:append_minute_tick)

    # Instrument fetch mock
    allow(instrument).to receive(:intraday_ohlc).and_return(raw_candle_response)
  end

  describe '#backfill' do
    context 'when DhanHQ returns candle data' do
      it 'returns success: true' do
        result = service.backfill(instrument: instrument, interval: 1)
        expect(result[:success]).to be true
      end

      it 'reports the number of candles fetched' do
        result = service.backfill(instrument: instrument, interval: 1)
        expect(result[:candles_fetched]).to eq(2)
      end

      it 'stores two synthetic ticks per candle (open + close)' do
        service.backfill(instrument: instrument, interval: 1)
        # 2 candles × 2 ticks = 4 appends
        expect(OptionsBuying::StateStore).to have_received(:append_minute_tick).exactly(4).times
      end

      it 'uses open price for the first synthetic tick of each candle' do
        captured = []
        allow(OptionsBuying::StateStore).to receive(:append_minute_tick) do |_sid, _bucket, payload|
          captured << payload
        end
        service.backfill(instrument: instrument, interval: 1)
        open_ltps = captured.pluck(:ltp)
        expect(open_ltps).to include(100.0) # open of first candle
      end

      it 'resets the circuit breaker failure counter on success' do
        service.backfill(instrument: instrument, interval: 1)
        expect(redis_double).to have_received(:del).with(described_class::FAILURE_CTR_KEY)
      end
    end

    context 'when DhanHQ returns nil (network / token error)' do
      before { allow(instrument).to receive(:intraday_ohlc).and_return(nil) }

      it 'returns success: false' do
        result = service.backfill(instrument: instrument, interval: 1)
        expect(result[:success]).to be false
      end

      it 'increments the failure counter' do
        service.backfill(instrument: instrument, interval: 1)
        expect(redis_double).to have_received(:incr).with(described_class::FAILURE_CTR_KEY)
      end
    end

    context 'when circuit breaker is open' do
      before do
        allow(redis_double).to receive(:exists?).with(described_class::CIRCUIT_OPEN_KEY).and_return(true)
      end

      it 'returns success: false with circuit_open error' do
        result = service.backfill(instrument: instrument, interval: 1)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('circuit_open')
      end

      it 'does not call intraday_ohlc' do
        service.backfill(instrument: instrument, interval: 1)
        expect(instrument).not_to have_received(:intraday_ohlc)
      end
    end

    context 'when DhanHQ raises on first attempt but succeeds on retry' do
      let(:call_count) { { n: 0 } }

      before do
        allow(instrument).to receive(:intraday_ohlc) do
          call_count[:n] += 1
          raise 'transient error' if call_count[:n] == 1

          raw_candle_response
        end
        allow(service).to receive(:sleep) # stub sleep for speed
      end

      it 'succeeds on the second attempt' do
        result = service.backfill(instrument: instrument, interval: 1)
        expect(result[:success]).to be true
      end
    end

    context 'when from_date / to_date are provided' do
      it 'passes them to intraday_ohlc' do
        service.backfill(
          instrument: instrument,
          interval: 1,
          from_date: '2026-06-19 10:00:00',
          to_date: '2026-06-19 10:30:00'
        )
        expect(instrument).to have_received(:intraday_ohlc).with(
          hash_including(interval: '1', from_date: '2026-06-19 10:00:00', to_date: '2026-06-19 10:30:00')
        )
      end
    end

    context 'bucket-bucket range returned' do
      it 'provides min_bucket and max_bucket in the result' do
        result = service.backfill(instrument: instrument, interval: 1)
        expect(result[:min_bucket]).to be_a(Integer)
        expect(result[:max_bucket]).to be_a(Integer)
        expect(result[:max_bucket]).to be >= result[:min_bucket]
      end
    end
  end

  describe '#backfill_all' do
    let(:tracker)    { instance_double(PositionTracker, instrument: instrument, security_id: '52175') }
    let(:cache)      { instance_double(Positions::ActivePositionsCache, active_trackers: [tracker]) }
    let(:index_cfg)  { [{ key: 'NIFTY', symbol: 'NIFTY', security_id: '13', exchange_segment: 'IDX_I' }] }
    let(:idx_inst)   { build_stubbed(:instrument, security_id: '13', symbol_name: 'NIFTY') }
    let(:idx_cache)  { instance_double(IndexInstrumentCache) }

    before do
      allow(Positions::ActivePositionsCache).to receive(:instance).and_return(cache)
      allow(IndexConfigLoader).to receive(:load_indices).and_return(index_cfg)
      allow(IndexInstrumentCache).to receive(:instance).and_return(idx_cache)
      allow(idx_cache).to receive(:get_or_fetch).and_return(idx_inst)
      allow(idx_inst).to receive(:intraday_ohlc).and_return(raw_candle_response)
      allow(instrument).to receive(:intraday_ohlc).and_return(raw_candle_response)

      # Simulate a gap: no ticks in any bucket
      allow(OptionsBuying::StateStore).to receive(:minute_ticks).and_return([])
    end

    it 'backfills both position instruments and watchlist indices' do
      expect(service).to receive(:backfill).at_least(:twice).and_call_original
      service.backfill_all(interval: 1, missing_minutes_threshold: 1)
    end
  end

  describe 'rate limiting' do
    it 'sleeps when a request was made within RATE_LIMIT_INTERVAL' do
      allow(redis_double).to receive(:get).with(described_class::RATE_TS_KEY)
                                          .and_return((Time.current.to_i - 1).to_s)
      allow(service).to receive(:sleep)

      service.backfill(instrument: instrument, interval: 1)
      expect(service).to have_received(:sleep).with(1)
    end
  end
end
