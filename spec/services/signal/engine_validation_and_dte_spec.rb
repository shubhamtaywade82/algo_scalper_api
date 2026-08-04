# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.resolve_nearest_expiry_date' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:expiry) { Date.new(2026, 4, 10) }

    it 'returns nearest expiry from DerivativeChainAnalyzer' do
      analyzer = instance_double(Options::DerivativeChainAnalyzer, nearest_expiry: expiry)
      allow(Options::DerivativeChainAnalyzer).to receive(:new).with(index_key: 'NIFTY').and_return(analyzer)

      out = described_class.send(:resolve_nearest_expiry_date, index_cfg: index_cfg)
      expect(out).to eq(expiry)
    end
  end

  describe '.entry_dte_guard_blocks?' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:today) { Date.new(2026, 4, 6) }

    before do
      allow(Time.zone).to receive(:today).and_return(today)
    end

    it 'returns false when guard disabled' do
      blocked = described_class.send(
        :entry_dte_guard_blocks?,
        index_cfg: index_cfg,
        signals_cfg: { entry_dte_guard: { enabled: false } },
        nearest_expiry: today + 1.day
      )
      expect(blocked).to be(false)
    end

    it 'returns true when DTE is at or below threshold' do
      blocked = described_class.send(
        :entry_dte_guard_blocks?,
        index_cfg: index_cfg,
        signals_cfg: {
          entry_dte_guard: { enabled: true, reject_when_days_to_expiry_lte: 1 }
        },
        nearest_expiry: today + 1.day
      )
      expect(blocked).to be(true)
    end

    it 'returns false when DTE is above threshold' do
      blocked = described_class.send(
        :entry_dte_guard_blocks?,
        index_cfg: index_cfg,
        signals_cfg: {
          entry_dte_guard: { enabled: true, reject_when_days_to_expiry_lte: 1 }
        },
        nearest_expiry: today + 3.days
      )
      expect(blocked).to be(false)
    end
  end
end
