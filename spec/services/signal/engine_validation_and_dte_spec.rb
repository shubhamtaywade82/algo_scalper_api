# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::ExpiryGate do
  describe '.resolve_nearest_expiry_date' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:expiry) { Date.new(2026, 4, 10) }

    it 'returns expiry from no_trade_gate when present' do
      out = described_class.resolve_nearest_expiry_date(
        index_cfg: index_cfg,
        no_trade_gate: { expiry_date: expiry, chain_data: {} }
      )
      expect(out).to eq(expiry)
    end

    it 'falls back to DerivativeChainAnalyzer when expiry is nil' do
      analyzer = instance_double(Options::DerivativeChainAnalyzer, nearest_expiry: expiry)
      allow(Options::DerivativeChainAnalyzer).to receive(:new).with(index_key: 'NIFTY').and_return(analyzer)

      out = described_class.resolve_nearest_expiry_date(
        index_cfg: index_cfg,
        no_trade_gate: { expiry_date: nil, chain_data: nil }
      )
      expect(out).to eq(expiry)
    end
  end
end
