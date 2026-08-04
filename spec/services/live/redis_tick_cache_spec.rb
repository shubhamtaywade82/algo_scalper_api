# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RedisTickCache do
  let(:cache) { described_class.instance }
  let(:redis_double) { instance_double(Redis) }

  before do
    allow(cache).to receive(:redis).and_return(redis_double)
    allow(redis_double).to receive(:hgetall).and_return({})
    allow(redis_double).to receive(:hmset)
  end

  describe '#store_tick' do
    it 'sets a 1-hour TTL on the tick key after storing' do
      expect(redis_double).to receive(:expire).with('tick:NSE_FNO:50073', 3600)
      cache.store_tick(segment: 'NSE_FNO', security_id: '50073', data: { ltp: 100.0, ts: Time.current.to_i })
    end
  end
end
