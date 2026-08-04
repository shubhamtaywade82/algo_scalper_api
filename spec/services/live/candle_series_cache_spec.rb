# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::CandleSeriesCache do
  let(:instrument) do
    build_stubbed(:instrument, security_id: '52175', symbol_name: 'NIFTY24500CE')
  end

  let(:redis_double) { instance_double(Redis) }

  let(:candle_payload) do
    {
      'updated_at' => Time.current.to_i,
      'candles'    => Array.new(25) do |i|
        ts = (Time.zone.parse('2026-06-19 09:15:00') + i.minutes).utc.iso8601(3)
        { 'timestamp' => ts, 'open' => 100.0 + i, 'high' => 106.0 + i,
          'low' => 98.0 + i, 'close' => 104.0 + i, 'volume' => 1000, 'oi' => 0 }
      end
    }
  end

  before do
    allow(described_class).to receive(:redis).and_return(redis_double)
  end

  describe '.fetch' do
    context 'when cache has >= MIN_CANDLES' do
      before do
        allow(redis_double).to receive(:get).and_return(candle_payload.to_json)
      end

      it 'returns a CandleSeries' do
        result = described_class.fetch(instrument: instrument, interval: 5)
        expect(result).to be_a(CandleSeries)
      end

      it 'contains all cached candles' do
        result = described_class.fetch(instrument: instrument, interval: 5)
        expect(result.candles.size).to eq(25)
      end

      it 'does not trigger a backfill' do
        expect(Live::HistoricalBackfillService).not_to receive(:new)
        described_class.fetch(instrument: instrument, interval: 5)
      end
    end

    context 'when cache is empty and backfill: true' do
      let(:backfill_service) { instance_double(Live::HistoricalBackfillService) }

      before do
        allow(redis_double).to receive(:get).and_return(nil, candle_payload.to_json)
        allow(Live::HistoricalBackfillService).to receive(:new).and_return(backfill_service)
        allow(backfill_service).to receive(:backfill).and_return({ success: true })
      end

      it 'triggers a backfill' do
        described_class.fetch(instrument: instrument, interval: 5)
        expect(backfill_service).to have_received(:backfill)
      end

      it 'returns a CandleSeries after backfill' do
        result = described_class.fetch(instrument: instrument, interval: 5)
        expect(result).to be_a(CandleSeries)
      end
    end

    context 'when cache is empty and backfill: false' do
      before do
        allow(redis_double).to receive(:get).and_return(nil)
      end

      it 'returns nil' do
        result = described_class.fetch(instrument: instrument, interval: 5, backfill: false)
        expect(result).to be_nil
      end
    end

    context 'when Redis returns malformed JSON' do
      before do
        allow(redis_double).to receive(:get).and_return('not valid json!!!')
      end

      it 'returns nil without raising' do
        expect { described_class.fetch(instrument: instrument, interval: 5, backfill: false) }.not_to raise_error
      end
    end
  end

  describe '.append_tick persistence hook' do
    let(:index_instrument) { build_stubbed(:instrument, :nifty_index) }
    let(:tick) { { ltp: 25_010.0, volume: 100, oi: 0 } }

    before do
      allow(redis_double).to receive(:set)
    end

    context 'when the bucket rolls over for a 1m index candle with a prior forming bar' do
      let(:existing_payload) do
        {
          'updated_at' => 1.minute.ago.to_i,
          'candles' => [
            { 'timestamp' => 1.minute.ago.beginning_of_minute.utc.iso8601(3),
              'open' => 25_000.0, 'high' => 25_020.0, 'low' => 24_990.0, 'close' => 25_005.0,
              'volume' => 500, 'oi' => 0 }
          ]
        }
      end

      before do
        allow(redis_double).to receive(:get).and_return(existing_payload.to_json)
      end

      it 'enqueues the completed bar via Candles::Persister' do
        expect(Candles::Persister).to receive(:enqueue).with(
          instrument: index_instrument,
          interval: 1,
          candles: [existing_payload['candles'].first],
          source: 'live'
        )

        described_class.append_tick(instrument: index_instrument, tick: tick, interval: 1)
      end
    end

    context 'when the bucket has not rolled over yet (same forming candle)' do
      let(:same_bucket_payload) do
        now_bucket = Time.current.to_i - (Time.current.to_i % 60)
        {
          'updated_at' => Time.current.to_i,
          'candles' => [
            { 'timestamp' => Time.at(now_bucket).utc.iso8601(3),
              'open' => 25_000.0, 'high' => 25_020.0, 'low' => 24_990.0, 'close' => 25_005.0,
              'volume' => 500, 'oi' => 0 }
          ]
        }
      end

      before do
        allow(redis_double).to receive(:get).and_return(same_bucket_payload.to_json)
      end

      it 'does not enqueue anything' do
        expect(Candles::Persister).not_to receive(:enqueue)

        described_class.append_tick(instrument: index_instrument, tick: tick, interval: 1)
      end
    end

    context 'for a non-1m interval (e.g. 5m)' do
      let(:existing_payload) do
        {
          'updated_at' => 5.minutes.ago.to_i,
          'candles' => [
            { 'timestamp' => 5.minutes.ago.beginning_of_hour.utc.iso8601(3),
              'open' => 25_000.0, 'high' => 25_020.0, 'low' => 24_990.0, 'close' => 25_005.0,
              'volume' => 500, 'oi' => 0 }
          ]
        }
      end

      before do
        allow(redis_double).to receive(:get).and_return(existing_payload.to_json)
      end

      it 'still calls Persister.enqueue (Persister itself no-ops for non-1m intervals; the cache does not special-case it)' do
        expect(Candles::Persister).to receive(:enqueue).with(hash_including(interval: 5))

        described_class.append_tick(instrument: index_instrument, tick: tick, interval: 5)
      end
    end

    context 'when there is no prior forming bar (first tick of the day)' do
      before do
        allow(redis_double).to receive(:get).and_return(nil)
      end

      it 'does not enqueue anything' do
        expect(Candles::Persister).not_to receive(:enqueue)

        described_class.append_tick(instrument: index_instrument, tick: tick, interval: 1)
      end
    end

    context 'when Candles::Persister.enqueue raises' do
      let(:existing_payload) do
        {
          'updated_at' => 1.minute.ago.to_i,
          'candles' => [
            { 'timestamp' => 1.minute.ago.beginning_of_minute.utc.iso8601(3),
              'open' => 25_000.0, 'high' => 25_020.0, 'low' => 24_990.0, 'close' => 25_005.0,
              'volume' => 500, 'oi' => 0 }
          ]
        }
      end

      before do
        allow(redis_double).to receive(:get).and_return(existing_payload.to_json)
        allow(Candles::Persister).to receive(:enqueue).and_raise(StandardError, 'enqueue boom')
      end

      it 'does not propagate the error out of append_tick' do
        expect do
          described_class.append_tick(instrument: index_instrument, tick: tick, interval: 1)
        end.not_to raise_error
      end

      it 'still writes the new forming candle to Redis' do
        described_class.append_tick(instrument: index_instrument, tick: tick, interval: 1)

        expect(redis_double).to have_received(:set) do |_key, value, **_opts|
          candles = JSON.parse(value)['candles']
          expect(candles.last['close']).to eq(tick[:ltp])
        end
      end
    end
  end

  describe '.refresh' do
    let(:backfill_service) { instance_double(Live::HistoricalBackfillService) }

    before do
      allow(redis_double).to receive(:del)
      allow(Live::HistoricalBackfillService).to receive(:new).and_return(backfill_service)
      allow(backfill_service).to receive(:backfill).and_return({ success: true })
      allow(redis_double).to receive(:get).and_return(candle_payload.to_json)
    end

    it 'deletes the existing cache key' do
      described_class.refresh(instrument: instrument, interval: 5)
      expect(redis_double).to have_received(:del).with("live:candles:52175:5")
    end

    it 'triggers a backfill' do
      described_class.refresh(instrument: instrument, interval: 5)
      expect(backfill_service).to have_received(:backfill)
    end
  end

  describe '.append_tick' do
    let(:tick) { { ltp: 250.0, volume: 500, oi: 1000 } }

    context 'when no existing cache entry' do
      before do
        allow(redis_double).to receive(:get).and_return(nil)
        allow(redis_double).to receive(:set)
      end

      it 'creates a new forming candle' do
        described_class.append_tick(instrument: instrument, tick: tick, interval: 5)
        expect(redis_double).to have_received(:set) do |key, value, **_opts|
          parsed = JSON.parse(value)
          expect(parsed['candles'].last['open']).to eq(250.0)
          expect(parsed['candles'].last['close']).to eq(250.0)
        end
      end
    end

    context 'when a forming candle already exists for the current bucket' do
      let(:current_bucket_iso) do
        now = Time.current
        bucket = now.to_i - (now.to_i % (5 * 60))
        Time.at(bucket).utc.iso8601(3)
      end

      let(:existing_payload) do
        {
          'updated_at' => Time.current.to_i,
          'candles'    => [
            { 'timestamp' => current_bucket_iso, 'open' => 240.0, 'high' => 245.0,
              'low' => 238.0, 'close' => 243.0, 'volume' => 200, 'oi' => 0 }
          ]
        }.to_json
      end

      before do
        allow(redis_double).to receive(:get).and_return(existing_payload)
        allow(redis_double).to receive(:set)
      end

      it 'updates high when LTP exceeds current high' do
        described_class.append_tick(instrument: instrument, tick: { ltp: 260.0, volume: 100 }, interval: 5)
        expect(redis_double).to have_received(:set) do |_key, value, **_opts|
          parsed = JSON.parse(value)
          expect(parsed['candles'].last['high']).to eq(260.0)
          expect(parsed['candles'].last['open']).to eq(240.0) # open must not change
        end
      end

      it 'updates low when LTP is below current low' do
        described_class.append_tick(instrument: instrument, tick: { ltp: 230.0, volume: 100 }, interval: 5)
        expect(redis_double).to have_received(:set) do |_key, value, **_opts|
          parsed = JSON.parse(value)
          expect(parsed['candles'].last['low']).to eq(230.0)
        end
      end

      it 'increments volume' do
        described_class.append_tick(instrument: instrument, tick: { ltp: 243.0, volume: 50 }, interval: 5)
        expect(redis_double).to have_received(:set) do |_key, value, **_opts|
          parsed = JSON.parse(value)
          expect(parsed['candles'].last['volume']).to eq(250)
        end
      end
    end

    context 'when ltp is zero' do
      before do
        allow(redis_double).to receive(:get)
        allow(redis_double).to receive(:set)
      end

      it 'does not write to Redis' do
        described_class.append_tick(instrument: instrument, tick: { ltp: 0, volume: 0 }, interval: 5)
        expect(redis_double).not_to have_received(:set)
      end
    end
  end

  describe '.store_candles' do
    let(:candles) do
      [
        { timestamp: Time.zone.parse('2026-06-19 09:15:00'), open: 100.0, high: 105.0,
          low: 98.0, close: 103.0, volume: 1000, oi: 0 },
        { timestamp: Time.zone.parse('2026-06-19 09:20:00'), open: 103.0, high: 110.0,
          low: 101.0, close: 108.0, volume: 1200, oi: 0 }
      ]
    end

    before do
      allow(redis_double).to receive(:get).and_return(nil)
      allow(redis_double).to receive(:set)
    end

    it 'stores candles sorted by timestamp' do
      described_class.store_candles(security_id: '52175', interval: 5, candles: candles)
      expect(redis_double).to have_received(:set) do |_key, value, **_opts|
        parsed = JSON.parse(value)
        ts = parsed['candles'].map { |c| c['timestamp'] }
        expect(ts).to eq(ts.sort)
      end
    end

    it 'merges with existing cached candles without duplicates' do
      existing = {
        'updated_at' => Time.current.to_i,
        'candles'    => [
          { 'timestamp' => Time.zone.parse('2026-06-19 09:15:00').utc.iso8601(3),
            'open' => 99.0, 'high' => 100.0, 'low' => 97.0, 'close' => 99.5, 'volume' => 800, 'oi' => 0 }
        ]
      }.to_json

      allow(redis_double).to receive(:get).and_return(existing)

      described_class.store_candles(security_id: '52175', interval: 5, candles: candles)

      expect(redis_double).to have_received(:set) do |_key, value, **_opts|
        parsed = JSON.parse(value)
        # 2 new + 1 old = 2 unique (09:15 is overwritten by new data)
        expect(parsed['candles'].size).to eq(2)
      end
    end
  end
end
