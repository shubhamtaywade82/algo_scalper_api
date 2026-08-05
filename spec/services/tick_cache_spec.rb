# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TickCache do
  include ActiveSupport::Testing::TimeHelpers

  let(:cache) { described_class.instance }
  let(:tick) { { segment: 'NSE_FNO', security_id: '12345', ltp: 100.5 } }

  before { cache.clear }

  describe '#fetch memory fast-path' do
    it 'returns the in-memory value without hitting Redis when freshly written' do
      allow(Live::RedisTickCache.instance).to receive(:store_tick)
      allow(Live::RedisTickCache.instance).to receive(:fetch_tick)

      cache.put(tick)
      result = cache.fetch('NSE_FNO', '12345')

      expect(result[:ltp]).to eq(100.5)
      expect(Live::RedisTickCache.instance).not_to have_received(:fetch_tick)
    end

    it 'falls through to Redis once the memory entry is older than the TTL' do
      allow(Live::RedisTickCache.instance).to receive(:store_tick)
      cache.put(tick)

      travel_to(described_class::MEMORY_TTL.seconds.from_now + 5.seconds) do
        allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(
          { segment: 'NSE_FNO', security_id: '12345', ltp: 101.0 }
        )

        result = cache.fetch('NSE_FNO', '12345')

        expect(result[:ltp]).to eq(101.0)
        expect(Live::RedisTickCache.instance).to have_received(:fetch_tick)
      end
    end

    it 'hits Redis when nothing is in memory yet' do
      allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return(
        { segment: 'NSE_FNO', security_id: '12345', ltp: 99.0 }
      )

      result = cache.fetch('NSE_FNO', '12345')

      expect(result[:ltp]).to eq(99.0)
      expect(Live::RedisTickCache.instance).to have_received(:fetch_tick)
    end

    it 'returns nil when Redis has nothing and memory is empty' do
      allow(Live::RedisTickCache.instance).to receive(:fetch_tick).and_return({})

      expect(cache.fetch('NSE_FNO', '99999')).to be_nil
    end
  end
end
