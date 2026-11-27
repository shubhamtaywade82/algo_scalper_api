# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RedisTickCache do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { described_class.instance }
  let(:redis_double) { instance_double(Redis) }

  before do
    allow(cache).to receive(:redis).and_return(redis_double)
    allow(redis_double).to receive(:hgetall).and_return({})
    allow(redis_double).to receive(:hmset)
  end

  describe '#store_tick' do
    it 'sets a 24-hour TTL on the tick key after storing' do
      allow(redis_double).to receive(:expire)
      cache.store_tick(segment: 'NSE_FNO', security_id: '50073', data: { ltp: 100.0, ts: Time.current.to_i })
      expect(redis_double).to have_received(:expire).with('tick:NSE_FNO:50073', 86_400)
    end
  end

  describe '#prune_stale' do
    let(:now) { Time.zone.local(2026, 11, 27, 11, 45, 0) }
    let(:tick_key) { 'tick:NSE_FNO:59931' }

    before do
      travel_to(now)
      allow(cache).to receive_messages(protected_keys_set: Set.new, active_position_security_ids: Set.new)
      allow(Live::PositionIndex.instance).to receive(:tracked?).and_return(false)
      allow(redis_double).to receive(:scan_each).with(match: 'tick:*').and_yield(tick_key)
      allow(redis_double).to receive(:del)
    end

    it 'keeps keys whose cached_at is fresh even when exchange ts (ltt) is stale' do
      allow(redis_double).to receive(:hgetall).with(tick_key).and_return(
        { 'ts' => (now - 190.seconds).to_i.to_s, 'cached_at' => (now - 2.seconds).to_s }
      )

      cache.prune_stale(max_age: 60)

      expect(redis_double).not_to have_received(:del).with(tick_key)
    end

    it 'prunes keys whose cached_at is older than max_age' do
      allow(redis_double).to receive(:hgetall).with(tick_key).and_return(
        { 'ts' => (now - 190.seconds).to_i.to_s, 'cached_at' => (now - 90.seconds).to_s }
      )

      cache.prune_stale(max_age: 60)

      expect(redis_double).to have_received(:del).with(tick_key)
    end

    it 'falls back to ts when cached_at is absent' do
      allow(redis_double).to receive(:hgetall).with(tick_key).and_return(
        { 'ts' => (now - 120.seconds).to_i.to_s }
      )

      cache.prune_stale(max_age: 60)

      expect(redis_double).to have_received(:del).with(tick_key)
    end

    it 'prunes keys missing both cached_at and ts' do
      allow(redis_double).to receive(:hgetall).with(tick_key).and_return({ 'ltp' => '1770.0' })

      cache.prune_stale(max_age: 60)

      expect(redis_double).to have_received(:del).with(tick_key)
    end
  end
end
