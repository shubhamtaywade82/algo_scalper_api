# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::VWAPUtils do
  describe '.calculate_vwap' do
    it 'calculates VWAP using typical price (HLC/3)' do
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_100),
        build(:candle, high: 25_300, low: 25_100, close: 25_200)
      ]

      vwap = described_class.calculate_vwap(bars)

      # Typical prices: (25100+24900+25000)/3 = 25000, (25200+25000+25100)/3 = 25100, (25300+25100+25200)/3 = 25200
      # Average: (25000 + 25100 + 25200) / 3 = 25100
      expect(vwap).to be_within(1).of(25_100)
    end

    it 'returns nil when bars is empty' do
      vwap = described_class.calculate_vwap([])

      expect(vwap).to be_nil
    end
  end

  describe '.near_vwap?' do
    it 'returns true when price is within ±0.1% of VWAP' do
      vwap = 25_000
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_100),
        build(:candle, high: 25_300, low: 25_100, close: 25_025) # Within 0.1% of VWAP
      ]

      allow(described_class).to receive(:calculate_vwap).and_return(vwap)

      result = described_class.near_vwap?(bars, threshold_pct: 0.1)

      expect(result).to be true
    end

    it 'returns false when price is outside ±0.1% of VWAP' do
      vwap = 25_000
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_100),
        build(:candle, high: 25_300, low: 25_100, close: 25_100) # Outside 0.1% of VWAP
      ]

      allow(described_class).to receive(:calculate_vwap).and_return(vwap)

      result = described_class.near_vwap?(bars, threshold_pct: 0.1)

      expect(result).to be false
    end

    it 'returns false when bars is empty' do
      result = described_class.near_vwap?([])

      expect(result).to be false
    end

    it 'returns false when VWAP cannot be calculated' do
      bars = [build(:candle, high: 25_100, low: 24_900, close: 25_000)]

      allow(described_class).to receive(:calculate_vwap).and_return(nil)

      result = described_class.near_vwap?(bars)

      expect(result).to be false
    end
  end

  describe '.calculate_avwap' do
    it 'calculates AVWAP from anchor time' do
      anchor_time = 1.hour.ago
      bars = [
        build(:candle, timestamp: 2.hours.ago, high: 25_000, low: 24_900, close: 24_950),
        build(:candle, timestamp: anchor_time, high: 25_100, low: 24_950, close: 25_000),
        build(:candle, timestamp: 30.minutes.ago, high: 25_200, low: 25_000, close: 25_100)
      ]

      avwap = described_class.calculate_avwap(bars, anchor_time: anchor_time)

      # Should only include candles from anchor_time onwards
      expect(avwap).to be_within(1).of(25_050)
    end

    it 'uses first candle timestamp as default anchor' do
      bars = [
        build(:candle, timestamp: 1.hour.ago, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, timestamp: 30.minutes.ago, high: 25_200, low: 25_000, close: 25_100)
      ]

      avwap = described_class.calculate_avwap(bars)

      expect(avwap).to be_within(1).of(25_050)
    end

    it 'returns nil when bars is empty' do
      avwap = described_class.calculate_avwap([])

      expect(avwap).to be_nil
    end
  end

  describe '.trapped_between_vwap_avwap?' do
    it 'returns true when price is between VWAP and AVWAP' do
      vwap = 25_000
      avwap = 25_100
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_050) # Between VWAP and AVWAP
      ]

      allow(described_class).to receive(:calculate_vwap).and_return(vwap)
      allow(described_class).to receive(:calculate_avwap).and_return(avwap)

      result = described_class.trapped_between_vwap_avwap?(bars)

      expect(result).to be true
    end

    it 'returns false when price is outside VWAP/AVWAP range' do
      vwap = 25_000
      avwap = 25_100
      bars = [
        build(:candle, high: 25_100, low: 24_900, close: 25_000),
        build(:candle, high: 25_200, low: 25_000, close: 25_200) # Outside range
      ]

      allow(described_class).to receive(:calculate_vwap).and_return(vwap)
      allow(described_class).to receive(:calculate_avwap).and_return(avwap)

      result = described_class.trapped_between_vwap_avwap?(bars)

      expect(result).to be false
    end

    it 'returns false when bars is empty' do
      result = described_class.trapped_between_vwap_avwap?([])

      expect(result).to be false
    end

    it 'returns false when VWAP or AVWAP cannot be calculated' do
      bars = [build(:candle, high: 25_100, low: 24_900, close: 25_000)]

      allow(described_class).to receive(:calculate_vwap).and_return(nil)
      allow(described_class).to receive(:calculate_avwap).and_return(25_100)

      result = described_class.trapped_between_vwap_avwap?(bars)

      expect(result).to be false
    end
  end
end
