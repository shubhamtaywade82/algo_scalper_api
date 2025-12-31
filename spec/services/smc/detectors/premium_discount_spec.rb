# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::PremiumDiscount do
  describe '#equilibrium' do
    it 'computes equilibrium as average of high and low' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, high: 110, low: 90, close: 95))
      series.add_candle(build(:candle, high: 120, low: 80, close: 115))

      detector = described_class.new(series)
      expect(detector.equilibrium).to eq(100.0) # (120 + 80) / 2
    end

    it 'returns nil when no highs or lows available' do
      series = instance_double('CandleSeries', highs: [], lows: [], closes: [])
      detector = described_class.new(series)
      expect(detector.equilibrium).to be_nil
    end
  end

  describe '#premium?' do
    it 'returns true when price is above equilibrium' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, high: 110, low: 90, close: 95))
      series.add_candle(build(:candle, high: 120, low: 80, close: 115))

      detector = described_class.new(series)
      expect(detector.premium?).to be(true)
    end

    it 'returns false when price is below equilibrium' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, high: 110, low: 90, close: 95))
      series.add_candle(build(:candle, high: 120, low: 80, close: 85))

      detector = described_class.new(series)
      expect(detector.premium?).to be(false)
    end

    it 'returns false when equilibrium or price is nil' do
      series = instance_double('CandleSeries', highs: [], lows: [], closes: [])
      detector = described_class.new(series)
      expect(detector.premium?).to be(false)
    end
  end

  describe '#discount?' do
    it 'returns true when price is below equilibrium' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, high: 110, low: 90, close: 95))
      series.add_candle(build(:candle, high: 120, low: 80, close: 85))

      detector = described_class.new(series)
      expect(detector.discount?).to be(true)
    end

    it 'returns false when price is above equilibrium' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, high: 110, low: 90, close: 95))
      series.add_candle(build(:candle, high: 120, low: 80, close: 115))

      detector = described_class.new(series)
      expect(detector.discount?).to be(false)
    end

    it 'returns false when equilibrium or price is nil' do
      series = instance_double('CandleSeries', highs: [], lows: [], closes: [])
      detector = described_class.new(series)
      expect(detector.discount?).to be(false)
    end
  end

  describe '#to_h' do
    it 'serializes premium discount data' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, high: 110, low: 90, close: 95))
      series.add_candle(build(:candle, high: 120, low: 80, close: 115))

      detector = described_class.new(series)
      result = detector.to_h

      expect(result).to have_key(:high)
      expect(result).to have_key(:low)
      expect(result).to have_key(:equilibrium)
      expect(result).to have_key(:price)
      expect(result).to have_key(:premium)
      expect(result).to have_key(:discount)
      expect(result[:equilibrium]).to eq(100.0)
      expect(result[:premium]).to be(true)
    end
  end
end

