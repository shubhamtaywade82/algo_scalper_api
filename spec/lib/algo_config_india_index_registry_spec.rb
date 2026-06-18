# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig do
  before do
    described_class.reset!
    IndiaIndexRegistry.reset!
  end

  describe '.fetch' do
    it 'merges india_index_registry into indices' do
      allow(AlgoConfig::DocumentStore).to receive(:current_mutable_document).and_return(
        indices: [{ key: 'NIFTY', capital_alloc_pct: 0.30 }],
        paper_trading: { enabled: true },
        signals: { signal_tier: 'standard' }
      )
      allow(described_class).to receive(:load_signal_tier_presets).and_return(standard: {})

      nifty = described_class.fetch[:indices].find { |idx| idx[:key] == 'NIFTY' }

      expect(nifty[:sid]).to eq('13')
      expect(nifty[:segment]).to eq('IDX_I')
      expect(nifty[:lot]).to eq(75)
      expect(nifty[:execution][:earliest_entry_time]).to eq('09:30')
      expect(nifty[:capital_alloc_pct]).to eq(0.30)
    end
  end
end
