# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig do
  before do
    described_class.reset!
    IndiaIndexRegistry.reset!
  end

  describe '.fetch' do
    it 'merges DocumentStore index overlays by key and defers registry identity to IndexConfigLoader' do
      allow(AlgoConfig::DocumentStore).to receive(:current_mutable_document).and_return(
        indices: [{ key: 'NIFTY', capital_alloc_pct: 0.30 }],
        paper_trading: { enabled: true }
      )

      nifty = described_class.fetch[:indices].find { |idx| idx[:key] == 'NIFTY' }

      # The DocumentStore overlay wins over the algo.yml base entry...
      expect(nifty[:capital_alloc_pct]).to eq(0.30)

      # ...but canonical registry identity (sid/segment/lot/execution defaults)
      # is no longer merged into the raw config document —
      # IndiaIndexRegistry.merge_into is applied per index by IndexConfigLoader
      # when index configs are loaded.
      expect(nifty[:sid]).to be_nil
      expect(nifty[:segment]).to be_nil

      # The registry still supplies that identity on demand.
      merged = IndiaIndexRegistry.merge_into(key: 'NIFTY', capital_alloc_pct: 0.30)
      expect(merged[:sid]).to eq('13')
      expect(merged[:segment]).to eq('IDX_I')
      expect(merged[:lot]).to eq(75)
      expect(merged[:execution][:earliest_entry_time]).to eq('09:30')
      expect(merged[:capital_alloc_pct]).to eq(0.30)
    end
  end
end
