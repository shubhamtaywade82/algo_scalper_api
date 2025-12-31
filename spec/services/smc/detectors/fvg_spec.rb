# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::Fvg do
  describe '#gaps' do
    it 'returns empty array when no gaps are found' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 103, low: 100, close: 102))
      series.add_candle(build(:candle, open: 102, high: 104, low: 101, close: 103))

      detector = described_class.new(series)
      expect(detector.gaps).to eq([])
    end

    it 'detects bullish FVG when bullish candle creates gap' do
      series = build(:candle_series, :five_minute)
      # Previous candle
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      # Bullish candle (creates gap)
      series.add_candle(build(:candle, open: 101, high: 105, low: 100.5, close: 104))
      # Next candle (confirms gap - low is above previous high)
      series.add_candle(build(:candle, open: 104, high: 106, low: 103, close: 105))

      detector = described_class.new(series)
      gaps = detector.gaps

      expect(gaps.size).to eq(1)
      expect(gaps.first[:type]).to eq(:bullish)
      expect(gaps.first[:from]).to eq(102) # previous high
      expect(gaps.first[:to]).to eq(103) # next low
    end

    it 'detects bearish FVG when bearish candle creates gap' do
      series = build(:candle_series, :five_minute)
      # Previous candle
      series.add_candle(build(:candle, open: 105, high: 106, low: 104, close: 104.5))
      # Bearish candle (creates gap)
      series.add_candle(build(:candle, open: 104.5, high: 105, low: 100, close: 101))
      # Next candle (confirms gap - high is below previous low)
      series.add_candle(build(:candle, open: 101, high: 103.5, low: 100.5, close: 103))

      detector = described_class.new(series)
      gaps = detector.gaps

      expect(gaps.size).to eq(1)
      expect(gaps.first[:type]).to eq(:bearish)
      expect(gaps.first[:from]).to eq(103.5) # next high
      expect(gaps.first[:to]).to eq(104) # previous low
    end

    it 'detects multiple gaps in series' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 105, low: 100.5, close: 104))
      series.add_candle(build(:candle, open: 104, high: 106, low: 103, close: 105))
      series.add_candle(build(:candle, open: 105, high: 106, low: 104, close: 104.5))
      series.add_candle(build(:candle, open: 104.5, high: 105, low: 100, close: 101))
      series.add_candle(build(:candle, open: 101, high: 103.5, low: 100.5, close: 103))

      detector = described_class.new(series)
      gaps = detector.gaps

      expect(gaps.size).to eq(2)
      expect(gaps.first[:type]).to eq(:bullish)
      expect(gaps.last[:type]).to eq(:bearish)
    end

    it 'requires at least 3 candles to detect gaps' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 105, low: 100.5, close: 104))

      detector = described_class.new(series)
      expect(detector.gaps).to eq([])
    end
  end

  describe '#to_h' do
    it 'serializes gaps array' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 105, low: 100.5, close: 104))
      series.add_candle(build(:candle, open: 104, high: 106, low: 103, close: 105))

      detector = described_class.new(series)
      result = detector.to_h

      expect(result).to have_key(:gaps)
      expect(result[:gaps]).to be_an(Array)
      expect(result[:gaps].first[:type]).to eq(:bullish)
    end
  end
end

