# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::MergeUtil do
  describe '.deep_merge_hashes_with_arrays' do
    it 'recursively merges nested hashes' do
      base = { risk: { trailing: { drawdown_pct: 0.01 }, sl_pct: 0.02 } }
      overrides = { risk: { trailing: { activation_pct: 0.05 } } }

      result = described_class.deep_merge_hashes_with_arrays(base, overrides)

      expect(result[:risk][:trailing][:drawdown_pct]).to eq(0.01)
      expect(result[:risk][:trailing][:activation_pct]).to eq(0.05)
      expect(result[:risk][:sl_pct]).to eq(0.02)
    end

    it 'does not mutate the base hash' do
      base = { risk: { sl_pct: 0.02 } }
      overrides = { risk: { sl_pct: 0.05 } }

      described_class.deep_merge_hashes_with_arrays(base, overrides)

      expect(base[:risk][:sl_pct]).to eq(0.02)
    end

    it 'overrides scalar values' do
      base = { mode: 'paper' }
      overrides = { mode: 'live' }

      result = described_class.deep_merge_hashes_with_arrays(base, overrides)
      expect(result[:mode]).to eq('live')
    end

    it 'adds new keys from overrides' do
      base = { risk: { sl_pct: 0.02 } }
      overrides = { signals: { tier: 'standard' } }

      result = described_class.deep_merge_hashes_with_arrays(base, overrides)
      expect(result[:signals]).to eq(tier: 'standard')
      expect(result[:risk]).to eq(sl_pct: 0.02)
    end
  end

  describe '.merge_arrays' do
    it 'merges arrays of hashes by :key' do
      base = [{ key: 'NIFTY', enabled: true }, { key: 'SENSEX', enabled: true }]
      overrides = [{ key: 'NIFTY', enabled: false }]

      result = described_class.merge_arrays(base, overrides)

      expect(result.size).to eq(2)
      nifty = result.find { |i| i[:key] == 'NIFTY' }
      expect(nifty[:enabled]).to be(false)
    end

    it 'appends new items not present in base' do
      base = [{ key: 'NIFTY', enabled: true }]
      overrides = [{ key: 'BANKNIFTY', enabled: true }]

      result = described_class.merge_arrays(base, overrides)
      expect(result.size).to eq(2)
    end

    it 'replaces entire array when items lack :key' do
      base = [1, 2, 3]
      overrides = [4, 5]

      result = described_class.merge_arrays(base, overrides)
      expect(result).to eq([4, 5])
    end

    it 'does not mutate base array items' do
      base = [{ key: 'NIFTY', enabled: true, nested: { x: 1 } }]
      overrides = [{ key: 'NIFTY', nested: { y: 2 } }]

      described_class.merge_arrays(base, overrides)

      expect(base.first[:nested]).to eq(x: 1)
    end
  end
end
