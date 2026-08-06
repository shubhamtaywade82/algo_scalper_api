# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketState::FeatureStore do
  describe '.snapshot' do
    it 'returns an immutable feature snapshot with feature_snapshot_id' do
      snapshot = described_class.snapshot(:nifty)

      expect(snapshot[:feature_snapshot_id]).to start_with('feat_')
      expect(snapshot[:index_key]).to eq('nifty')
      expect(snapshot[:freshness]).to be_a(Hash)
      expect(snapshot[:features]).to be_a(Hash)
    end
  end
end
