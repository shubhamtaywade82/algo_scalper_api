# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::PositionRuntimeCache do
  subject(:cache) { described_class.instance }

  let(:tracker) { create(:position_tracker, :paper, segment: 'NSE_FNO') }

  before do
    cache.clear(tracker.id)
  end

  describe '#update_peak_premium!' do
    it 'stores peak in redis without db write' do
      expect do
        cache.update_peak_premium!(tracker, 250.5)
      end.not_to(change { tracker.reload.meta })

      expect(cache.peak_premium_for(tracker)).to eq(250.5)
    end
  end

  describe '#flush_to_meta!' do
    it 'merges runtime fields into meta hash' do
      cache.update_peak_premium!(tracker, 300.0)

      merged = cache.flush_to_meta!({ 'symbol' => 'TEST' }, tracker.id)

      expect(merged['symbol']).to eq('TEST')
      expect(merged['peak_premium']).to eq(300.0)
      expect(merged['peak_premium_at']).to be_present
    end
  end
end
