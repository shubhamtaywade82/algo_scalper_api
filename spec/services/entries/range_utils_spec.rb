# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::RangeUtils do
  describe '.range_pct' do
    it 'calculates percentage range correctly' do
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_100),
        build(:candle, high: 25_300, low: 25_100, close: 25_200)
      ]

      range_pct = described_class.range_pct(bars)

      # High: 25300, Low: 24900, Avg: 25100
      # Range: (25300 - 24900) / 25100 * 100 = 1.59%
      expect(range_pct).to be_within(0.1).of(1.59)
    end

    it 'returns 0.0 when bars is nil' do
      range_pct = described_class.range_pct(nil)

      expect(range_pct).to eq(0.0)
    end

    it 'returns 0.0 when bars is empty' do
      range_pct = described_class.range_pct([])

      expect(range_pct).to eq(0.0)
    end

    it 'handles single candle' do
      bars = [build(:candle, high: 25_100, low: 24_900, close: 25_000)]

      range_pct = described_class.range_pct(bars)

      # Range: (25100 - 24900) / 25000 * 100 = 0.8%
      expect(range_pct).to be_within(0.1).of(0.8)
    end
  end

  describe '.compressed?' do
    it 'returns true when range is below threshold' do
      bars = [
        build(:candle, high: 25_010, low: 24_990, close: 25_000),
        build(:candle, high: 25_020, low: 25_000, close: 25_010)
      ]

      result = described_class.compressed?(bars, threshold_pct: 0.1)

      expect(result).to be true
    end

    it 'returns false when range is above threshold' do
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_100)
      ]

      result = described_class.compressed?(bars, threshold_pct: 0.1)

      expect(result).to be false
    end
  end
end
