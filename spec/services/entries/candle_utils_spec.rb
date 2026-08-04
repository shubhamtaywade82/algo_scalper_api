# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::CandleUtils do
  describe '.wick_ratio' do
    it 'calculates wick-to-body ratio correctly for bullish candle' do
      candle = build(:candle, open: 25_000, high: 25_200, low: 24_800, close: 25_100)

      ratio = described_class.wick_ratio(candle)

      # Body: 25100 - 25000 = 100
      # Upper wick: 25200 - 25100 = 100
      # Lower wick: 25000 - 24800 = 200
      # Total wick: 300
      # Ratio: 300 / 100 = 3.0
      expect(ratio).to be_within(0.1).of(3.0)
    end

    it 'calculates wick-to-body ratio correctly for bearish candle' do
      candle = build(:candle, open: 25_100, high: 25_200, low: 24_800, close: 25_000)

      ratio = described_class.wick_ratio(candle)

      # Body: 25100 - 25000 = 100
      # Upper wick: 25200 - 25100 = 100
      # Lower wick: 25000 - 24800 = 200
      # Total wick: 300
      # Ratio: 300 / 100 = 3.0
      expect(ratio).to be_within(0.1).of(3.0)
    end

    it 'handles doji candle (zero body)' do
      candle = build(:candle, :doji, open: 25_000, high: 25_100, low: 24_900, close: 25_000)

      ratio = described_class.wick_ratio(candle)

      # Body: 0, so ratio should be high
      expect(ratio).to be > 10
    end
  end

  describe '.avg_wick_ratio' do
    it 'calculates average wick ratio for multiple candles' do
      bars = [
        build(:candle, open: 25_000, high: 25_100, low: 24_950, close: 25_050), # Ratio ~1.0
        build(:candle, open: 25_050, high: 25_200, low: 25_000, close: 25_150), # Ratio ~1.0
        build(:candle, open: 25_150, high: 25_300, low: 25_100, close: 25_250) # Ratio ~1.0
      ]

      avg_ratio = described_class.avg_wick_ratio(bars)

      expect(avg_ratio).to be_within(0.5).of(1.0)
    end

    it 'returns 0.0 when bars is empty' do
      avg_ratio = described_class.avg_wick_ratio([])

      expect(avg_ratio).to eq(0.0)
    end
  end

  describe '.alternating_engulfing?' do
    it 'detects alternating engulfing candles' do
      bars = [
        build(:candle, :bullish, open: 25_000, high: 25_100, low: 24_950, close: 25_050),
        build(:candle, :bearish, open: 25_050, high: 25_100, low: 24_900, close: 24_950), # Engulfs previous
        build(:candle, :bullish, open: 24_950, high: 25_150, low: 24_900, close: 25_100) # Engulfs previous
      ]

      result = described_class.alternating_engulfing?(bars)

      expect(result).to be true
    end

    it 'returns false when no alternating engulfing pattern' do
      bars = [
        build(:candle, :bullish, open: 25_000, high: 25_100, low: 24_950, close: 25_050),
        build(:candle, :bullish, open: 25_050, high: 25_150, low: 25_000, close: 25_100),
        build(:candle, :bullish, open: 25_100, high: 25_200, low: 25_050, close: 25_150)
      ]

      result = described_class.alternating_engulfing?(bars)

      expect(result).to be false
    end
  end

  describe '.inside_bar_count' do
    it 'counts consecutive inside bars' do
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_050, low: 24_950, close: 25_000), # Inside bar
        build(:candle, high: 25_030, low: 24_970, close: 25_000), # Inside bar
        build(:candle, high: 25_020, low: 24_980, close: 25_000) # Inside bar
      ]

      count = described_class.inside_bar_count(bars)

      expect(count).to eq(3)
    end

    it 'returns 0 when no inside bars' do
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_100),
        build(:candle, high: 25_300, low: 25_100, close: 25_200)
      ]

      count = described_class.inside_bar_count(bars)

      expect(count).to eq(0)
    end
  end
end
