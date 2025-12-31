# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::Structure do
  describe '#trend' do
    it 'returns :unknown with insufficient swings' do
      series = instance_double('CandleSeries', candles: [], closes: [])
      allow(series).to receive(:swing_high?).and_return(false)
      allow(series).to receive(:swing_low?).and_return(false)

      detector = described_class.new(series)
      expect(detector.trend).to eq(:unknown)
    end

    it 'returns :bullish when last swing is high and previous is low' do
      candles = [
        build(:candle, high: 100, low: 90),
        build(:candle, high: 101, low: 89),
        build(:candle, high: 110, low: 95) # swing high
      ]
      series = instance_double('CandleSeries', candles: candles, closes: [95, 96, 97])

      allow(series).to receive(:swing_high?) { |i| i == 2 }
      allow(series).to receive(:swing_low?) { |i| i == 1 }

      detector = described_class.new(series)
      expect(detector.trend).to eq(:bullish)
    end
  end

  describe '#bos?' do
    it 'returns true when close breaks last swing high' do
      candles = [
        build(:candle, high: 100, low: 90),
        build(:candle, high: 110, low: 95)
      ]
      series = instance_double('CandleSeries', candles: candles, closes: [95, 120])

      allow(series).to receive(:swing_high?) { |i| i == 1 }
      allow(series).to receive(:swing_low?).and_return(false)

      detector = described_class.new(series)
      expect(detector.bos?).to be(true)
    end
  end

  describe '#choch?' do
    it 'returns false when there is not enough swing context' do
      candles = [build(:candle)]
      series = instance_double('CandleSeries', candles: candles, closes: [1.0])
      allow(series).to receive(:swing_high?).and_return(false)
      allow(series).to receive(:swing_low?).and_return(false)

      detector = described_class.new(series)
      expect(detector.choch?).to be(false)
    end
  end
end

