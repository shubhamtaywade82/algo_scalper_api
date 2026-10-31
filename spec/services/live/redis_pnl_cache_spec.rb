# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RedisPnlCache do
  # The class is a Singleton; reset_singletons clears @redis before each test
  # so we can inject a fresh mock per example.
  let(:redis) { instance_double(Redis) }
  let(:cache) do
    inst = described_class.instance
    inst.instance_variable_set(:@redis, redis)
    inst.instance_variable_set(:@sync_timestamps, {})
    inst
  end

  before do
    allow(redis).to receive(:hset)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:ttl).and_return(0)
    allow(redis).to receive(:del)
    allow(redis).to receive(:scan_each)
    allow(redis).to receive(:ping).and_return('PONG')
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:debug)
    allow(AlgoConfig).to receive(:fetch).and_return({})
  end

  describe '#store_pnl' do
    context 'when redis is unavailable' do
      let(:cache) do
        inst = described_class.instance
        inst.instance_variable_set(:@redis, nil)
        inst
      end

      it 'returns false without raising' do
        result = cache.store_pnl(tracker_id: 42, pnl: 100.0, ltp: 250.0, hwm: 150.0)
        expect(result).to be false
      end
    end

    it 'persists a hash with the core pnl fields under the tracker key' do
      expect(redis).to receive(:hset) do |key, hash|
        expect(key).to eq('pnl:tracker:42')
        expect(hash['pnl']).to eq('100.0')
        expect(hash['ltp']).to eq('250.0')
        expect(hash['hwm_pnl']).to eq('150.0')
        true
      end
      cache.store_pnl(tracker_id: 42, pnl: 100.0, ltp: 250.0, hwm: 150.0)
    end

    it 'refreshes TTL when below half of TTL_SECONDS' do
      allow(redis).to receive(:ttl).and_return(Live::RedisPnlCache::TTL_SECONDS / 4)
      expect(redis).to receive(:expire).with('pnl:tracker:7', Live::RedisPnlCache::TTL_SECONDS)
      cache.store_pnl(tracker_id: 7, pnl: 1.0, ltp: 1.0, hwm: 1.0)
    end

    it 'leaves TTL alone when above half of TTL_SECONDS' do
      allow(redis).to receive(:ttl).and_return(Live::RedisPnlCache::TTL_SECONDS * 0.75)
      expect(redis).not_to receive(:expire)
      cache.store_pnl(tracker_id: 7, pnl: 1.0, ltp: 1.0, hwm: 1.0)
    end

    it 'returns false on unexpected error' do
      allow(redis).to receive(:hset).and_raise(StandardError, 'redis exploded')
      result = cache.store_pnl(tracker_id: 99, pnl: 1.0, ltp: 1.0, hwm: 1.0)
      expect(result).to be false
    end

    context 'with a tracker object' do
      let(:tracker) do
        instance_double(
          PositionTracker,
          id: 42,
          entry_price: 100.0,
          quantity: 50,
          segment: 'NSE_FNO',
          security_id: '99999',
          symbol: 'NIFTY',
          side: 'long',
          order_no: 'ORD-1',
          paper?: false,
          created_at: Time.current - 60
        )
      end

      before do
        allow(tracker).to receive(:is_a?).with(PositionTracker).and_return(true)
        allow(Positions::ActiveCache.instance).to receive(:get_by_tracker_id).and_return(nil)
        allow(Positions::MetadataResolver).to receive(:index_key).with(tracker).and_return('NIFTY')
        allow(Positions::MetadataResolver).to receive(:direction).with(tracker).and_return(:bullish)
        allow(PositionTracker).to receive(:find_by).with(id: 42).and_return(nil)
      end

      it 'captures entry_price, quantity, segment, security_id, symbol, side, order_no, paper' do
        expect(redis).to receive(:hset) do |_key, hash|
          expect(hash['entry_price']).to eq('100.0')
          expect(hash['quantity']).to eq('50')
          expect(hash['segment']).to eq('NSE_FNO')
          expect(hash['security_id']).to eq('99999')
          expect(hash['symbol']).to eq('NIFTY')
          expect(hash['side']).to eq('long')
          expect(hash['order_no']).to eq('ORD-1')
          expect(hash['paper']).to eq('0')
          true
        end
        cache.store_pnl(tracker_id: 42, pnl: 5.0, ltp: 110.0, hwm: 8.0, tracker: tracker)
      end

      it 'computes price_change_pct, capital_deployed, time_in_position_sec, drawdown_rupees, drawdown_pct' do
        expect(redis).to receive(:hset) do |_key, hash|
          expect(hash['price_change_pct']).to eq('10.0')
          expect(hash['capital_deployed']).to eq('5000.0')
          expect(hash['time_in_position_sec']).to be_present
          expect(hash['drawdown_rupees']).to eq('3.0')
          expect(hash['drawdown_pct']).to be_present
          true
        end
        cache.store_pnl(tracker_id: 42, pnl: 5.0, ltp: 110.0, hwm: 8.0, tracker: tracker)
      end

      it 'resolves index_key and direction from MetadataResolver' do
        expect(redis).to receive(:hset) do |_key, hash|
          expect(hash['index_key']).to eq('NIFTY')
          expect(hash['direction']).to eq('bullish')
          true
        end
        cache.store_pnl(tracker_id: 42, pnl: 5.0, ltp: 110.0, hwm: 8.0, tracker: tracker)
      end
    end
  end

  describe '#fetch_pnl' do
    it 'returns nil when redis is unavailable' do
      cache.instance_variable_set(:@redis, nil)
      expect(cache.fetch_pnl(42)).to be_nil
    end

    it 'returns nil when key is missing' do
      allow(redis).to receive(:hgetall).and_return({})
      expect(cache.fetch_pnl(42)).to be_nil
    end

    it 'parses stored hash into typed fields' do
      allow(redis).to receive(:hgetall).and_return({
        'pnl' => '12.5', 'pnl_pct' => '2.5', 'ltp' => '250', 'hwm_pnl' => '20',
        'hwm_pnl_pct' => '4.0', 'timestamp' => '1700000000', 'updated_at' => '1700000100',
        'entry_price' => '100', 'quantity' => '50', 'segment' => 'NSE_FNO',
        'security_id' => '99999', 'symbol' => 'NIFTY', 'side' => 'long',
        'order_no' => 'ORD-1', 'paper' => '0', 'entry_timestamp' => '1699999000',
        'price_change_pct' => '10.0', 'capital_deployed' => '5000',
        'time_in_position_sec' => '60', 'drawdown_rupees' => '7.5',
        'drawdown_pct' => '37.5', 'index_key' => 'NIFTY', 'direction' => 'bullish',
        'sl_price' => '70.0', 'tp_price' => '160.0'
      })
      result = cache.fetch_pnl(42)
      expect(result[:pnl]).to eq(12.5)
      expect(result[:pnl_pct]).to eq(2.5)
      expect(result[:ltp]).to eq(250.0)
      expect(result[:hwm_pnl]).to eq(20.0)
      expect(result[:quantity]).to eq(50)
      expect(result[:paper]).to be false
      expect(result[:direction]).to eq(:bullish)
      expect(result[:sl_price]).to eq(70.0)
      expect(result[:tp_price]).to eq(160.0)
    end

    it 'returns nil on error' do
      allow(redis).to receive(:hgetall).and_raise(StandardError, 'redis gone')
      expect(cache.fetch_pnl(42)).to be_nil
    end
  end

  describe '#clear' do
    it 'deletes all keys matching the prefix' do
      allow(redis).to receive(:scan_each).and_yield('pnl:tracker:1').and_yield('pnl:tracker:2')
      expect(redis).to receive(:del).with('pnl:tracker:1')
      expect(redis).to receive(:del).with('pnl:tracker:2')
      expect(cache.clear).to be true
    end

    it 'returns false when redis is unavailable' do
      cache.instance_variable_set(:@redis, nil)
      expect(cache.clear).to be false
    end
  end

  describe '#clear_tracker' do
    it 'deletes only the given tracker key' do
      expect(redis).to receive(:del).with('pnl:tracker:42')
      expect(cache.clear_tracker(42)).to be true
    end
  end

  describe '#fetch_all' do
    it 'returns a hash of tracker_id => parsed data' do
      allow(redis).to receive(:scan_each).and_yield('pnl:tracker:1').and_yield('pnl:tracker:2')
      allow(redis).to receive(:hgetall).with('pnl:tracker:1').and_return({ 'pnl' => '10' })
      allow(redis).to receive(:hgetall).with('pnl:tracker:2').and_return({ 'pnl' => '20' })
      result = cache.fetch_all
      expect(result.keys).to contain_exactly(1, 2)
      expect(result[1][:pnl]).to eq(10.0)
      expect(result[2][:pnl]).to eq(20.0)
    end

    it 'returns empty hash when redis is unavailable' do
      cache.instance_variable_set(:@redis, nil)
      expect(cache.fetch_all).to eq({})
    end
  end

  describe '#health_check' do
    it 'returns ok when ping succeeds' do
      expect(cache.health_check).to eq({ status: :ok, message: 'ok' })
    end

    it 'returns error when ping raises' do
      allow(redis).to receive(:ping).and_raise(StandardError, 'connection lost')
      result = cache.health_check
      expect(result[:status]).to eq(:error)
      expect(result[:message]).to include('connection lost')
    end

    it 'returns error when redis is not initialized' do
      cache.instance_variable_set(:@redis, nil)
      result = cache.health_check
      expect(result[:status]).to eq(:error)
    end
  end

  describe '#sync_throttle_seconds' do
    it 'returns default when config returns 0' do
      allow(AlgoConfig).to receive(:fetch).and_return({})
      expect(cache.sync_throttle_seconds).to eq(Live::RedisPnlCache::DEFAULT_SYNC_THROTTLE_SECONDS)
    end

    it 'returns configured value from realtime.db_sync_interval_seconds' do
      allow(AlgoConfig).to receive(:fetch).and_return(realtime: { db_sync_interval_seconds: 60 })
      expect(cache.sync_throttle_seconds).to eq(60.0)
    end

    it 'returns risk.realtime.db_sync_interval_seconds when set' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        realtime: { db_sync_interval_seconds: 60 },
        risk: { realtime: { db_sync_interval_seconds: 90 } }
      )
      expect(cache.sync_throttle_seconds).to eq(90.0)
    end

    it 'falls back to default when AlgoConfig raises' do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError)
      expect(cache.sync_throttle_seconds).to eq(Live::RedisPnlCache::DEFAULT_SYNC_THROTTLE_SECONDS)
    end
  end

  describe '#sync_pnl_to_database' do
    it 'returns nil when tracker is not found' do
      allow(PositionTracker).to receive(:find_by).with(id: 999).and_return(nil)
      expect(cache.sync_pnl_to_database(999, 10.0, 1.0, 15.0)).to be_nil
    end

    context 'with an active tracker' do
      let(:tracker) do
        instance_double(PositionTracker, id: 42, active?: true, high_water_mark_pnl: 5.0, meta: {})
      end

      before do
        allow(PositionTracker).to receive(:find_by).with(id: 42).and_return(tracker)
        allow(tracker).to receive(:update!)
      end

      it 'updates last_pnl_rupees, last_pnl_pct, high_water_mark_pnl' do
        expect(tracker).to receive(:update!) do |attrs|
          expect(attrs[:last_pnl_rupees]).to eq(BigDecimal('10.0'))
          expect(attrs[:last_pnl_pct]).to eq(BigDecimal('1.0'))
          expect(attrs[:high_water_mark_pnl]).to eq(BigDecimal('15.0'))
        end
        cache.sync_pnl_to_database(42, 10.0, 1.0, 15.0)
      end

      it 'stores hwm_pnl_pct in meta when provided' do
        expect(tracker).to receive(:update!) do |attrs|
          expect(attrs[:meta]['hwm_pnl_pct']).to eq(2.5)
        end
        cache.sync_pnl_to_database(42, 10.0, 1.0, 15.0, 2.5)
      end

      it 'preserves existing meta keys when adding hwm_pnl_pct' do
        allow(tracker).to receive(:meta).and_return({ 'existing' => 'value' })
        expect(tracker).to receive(:update!) do |attrs|
          expect(attrs[:meta]['existing']).to eq('value')
          expect(attrs[:meta]['hwm_pnl_pct']).to eq(2.5)
        end
        cache.sync_pnl_to_database(42, 10.0, 1.0, 15.0, 2.5)
      end
    end
  end

  describe '#sync_pnl_to_database_throttled' do
    it 'skips DB sync when within throttle window' do
      cache.instance_variable_set(:@sync_timestamps, 42 => Time.current)
      allow(AlgoConfig).to receive(:fetch).and_return({})
      expect(cache).not_to receive(:sync_pnl_to_database)
      cache.sync_pnl_to_database_throttled(42, 10.0, 1.0, 15.0)
    end

    it 'performs DB sync when outside throttle window' do
      cache.instance_variable_set(:@sync_timestamps, 42 => Time.current - 120)
      allow(AlgoConfig).to receive(:fetch).and_return({})
      expect(cache).to receive(:sync_pnl_to_database).with(42, 10.0, 1.0, 15.0, nil)
      cache.sync_pnl_to_database_throttled(42, 10.0, 1.0, 15.0)
    end

    it 'performs DB sync when no previous timestamp' do
      allow(AlgoConfig).to receive(:fetch).and_return({})
      expect(cache).to receive(:sync_pnl_to_database).with(42, 10.0, 1.0, 15.0, nil)
      cache.sync_pnl_to_database_throttled(42, 10.0, 1.0, 15.0)
    end

    it 'returns nil when tracker_id is nil' do
      expect(cache.sync_pnl_to_database_throttled(nil, 10.0, 1.0, 15.0)).to be_nil
    end
  end

  describe '#purge_exited!' do
    it 'deletes keys not in the active set' do
      allow(Positions::ActivePositionsCache.instance).to receive(:active_tracker_ids).and_return(%w[1 2])
      allow(redis).to receive(:scan_each).and_yield('pnl:tracker:1').and_yield('pnl:tracker:3').and_yield('pnl:tracker:99')
      expect(redis).to receive(:del).with('pnl:tracker:3')
      expect(redis).to receive(:del).with('pnl:tracker:99')
      expect(redis).not_to receive(:del).with('pnl:tracker:1')
      expect(cache.purge_exited!).to be true
    end

    it 'returns false on error' do
      allow(Positions::ActivePositionsCache.instance).to receive(:active_tracker_ids).and_raise(StandardError)
      expect(cache.purge_exited!).to be false
    end

    it 'returns false when redis is unavailable' do
      cache.instance_variable_set(:@redis, nil)
      expect(cache.purge_exited!).to be false
    end
  end

  describe '#prune_except' do
    it 'clears trackers not in the allowed set' do
      allow(redis).to receive(:scan_each).and_yield('pnl:tracker:1').and_yield('pnl:tracker:2')
      expect(cache).to receive(:clear_tracker).with('2')
      expect(cache).not_to receive(:clear_tracker).with('1')
      cache.prune_except(%w[1])
    end
  end
end
