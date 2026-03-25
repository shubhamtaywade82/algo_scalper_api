# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::IndexSync do
  describe '#register' do
    it 'adds tracker metadata to position index' do
      tracker = instance_double(
        PositionTracker,
        id: 1,
        active?: true,
        entry_price: BigDecimal('100'),
        quantity: 25,
        metadata_for_index: { id: 1 }
      )
      index = instance_double(Live::PositionIndex, add: true)
      redis = instance_double(Redis, sadd: true)

      cache = instance_double(Live::RedisPnlCache)
      allow(cache).to receive(:send).and_return(redis)
      allow(Live::PositionIndex).to receive(:instance).and_return(index)
      allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)

      described_class.new(tracker: tracker).register

      expect(index).to have_received(:add).with(id: 1)
    end
  end

  describe '.clear_orphaned_redis_pnl!' do
    it 'clears trackers not in active redis set' do
      cache = instance_double(Live::RedisPnlCache)
      allow(cache).to receive(:each_tracker_key).and_yield('pnl:1', '1').and_yield('pnl:2', '2')
      allow(cache).to receive(:clear_tracker)
      allow(Live::RedisPnlCache).to receive(:instance).and_return(cache)
      allow(PositionTracker).to receive(:should_clear_orphaned?).and_return(true)
      allow(described_class).to receive(:active_tracker_ids_from_redis).and_return(Set.new(['1']))

      described_class.clear_orphaned_redis_pnl!

      expect(cache).to have_received(:clear_tracker).with('2')
    end
  end
end
