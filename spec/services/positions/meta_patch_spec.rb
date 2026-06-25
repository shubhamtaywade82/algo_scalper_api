# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::MetaPatch do
  let(:tracker) { create(:position_tracker, segment: 'NSE_FNO', meta: base_meta) }
  let(:base_meta) do
    {
      'config_snapshot' => { 'signals' => { 'enabled' => true } },
      'config_version' => 'v1',
      'be_set' => false,
      'highest_price' => 100.0
    }
  end
  let(:runtime_cache) { Live::PositionRuntimeCache.instance }

  before do
    runtime_cache.clear(tracker.id)
  end

  after do
    runtime_cache.clear(tracker.id)
  end

  describe '.apply!' do
    it 'writes runtime keys to Redis only' do
      before = tracker.meta.deep_stringify_keys
      after = before.merge('highest_price' => 110.0, 'peak_trend_score' => 42)

      described_class.apply!(tracker: tracker, before: before, after: after)

      cached = runtime_cache.fetch(tracker.id)
      expect(cached[:highest_price]).to eq(110.0)
      expect(cached[:peak_trend_score]).to eq(42.0)
      expect(tracker.reload.meta['highest_price']).to eq(100.0)
    end

    it 'merges non-promoted durable keys with jsonb patch, not full blob rewrite' do
      before = tracker.meta.deep_stringify_keys
      after = before.merge('entry_context' => { 'dte' => 0 })

      sql_calls = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql].to_s
        sql_calls << sql if sql.include?('position_trackers')
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        described_class.apply!(tracker: tracker, before: before, after: after)
      end

      update_sql = sql_calls.find { |sql| sql.include?('UPDATE') }
      expect(update_sql).to include('"entry_context"')
      expect(update_sql).not_to include('config_snapshot')
    end

    it 'persists durable meta changes' do
      before = tracker.meta.deep_stringify_keys
      after = before.merge('be_set' => true)

      described_class.apply!(tracker: tracker, before: before, after: after)

      tracker.reload
      expect(tracker.be_set?).to be(true)
      expect(tracker.meta['config_snapshot']).to eq(base_meta['config_snapshot'])
    end

    it 'skips writes when nothing changed' do
      before = tracker.meta.deep_stringify_keys
      after = before.dup
      allow(runtime_cache).to receive(:merge)
      allow(described_class).to receive(:merge_meta!)

      described_class.apply!(tracker: tracker, before: before, after: after)

      expect(runtime_cache).not_to have_received(:merge)
      expect(described_class).not_to have_received(:merge_meta!)
    end
  end

  describe '.merge_meta!' do
    it 'patches only supplied keys' do
      described_class.merge_meta!(tracker.id, 'profit_floor_rupees' => 250)

      tracker.reload
      expect(tracker.reload.profit_floor_rupees).to eq(250)
      expect(tracker.meta['config_snapshot']).to eq(base_meta['config_snapshot'])
    end
  end
end
