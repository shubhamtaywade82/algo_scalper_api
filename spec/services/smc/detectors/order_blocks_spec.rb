# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Detectors::OrderBlocks do
  describe '#bullish' do
    it 'returns nil when no bullish impulse is found' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 103, low: 100, close: 102))

      detector = described_class.new(series)
      expect(detector.bullish).to be_nil
    end

    it 'returns the bearish candle before a bullish impulse' do
      series = build(:candle_series, :five_minute)
      # Bearish candle (order block)
      series.add_candle(build(:candle, open: 105, high: 106, low: 104, close: 104.5))
      # Middle candle
      series.add_candle(build(:candle, open: 104.5, high: 105, low: 104, close: 104.8))
      # Bullish impulse (breaks above middle candle high)
      series.add_candle(build(:candle, open: 104.8, high: 108, low: 104, close: 107))

      detector = described_class.new(series)
      bullish_ob = detector.bullish

      expect(bullish_ob).not_to be_nil
      expect(bullish_ob.bearish?).to be(true)
      expect(bullish_ob.close).to eq(104.5)
    end

    it 'returns nil when impulse candle is not preceded by bearish candle' do
      series = build(:candle_series, :five_minute)
      # Bullish candle (not an order block)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      # Bullish impulse
      series.add_candle(build(:candle, open: 101, high: 108, low: 100, close: 107))

      detector = described_class.new(series)
      expect(detector.bullish).to be_nil
    end
  end

  describe '#bearish' do
    it 'returns nil when no bearish impulse is found' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 103, low: 100, close: 102))

      detector = described_class.new(series)
      expect(detector.bearish).to be_nil
    end

    it 'returns the bullish candle before a bearish impulse' do
      series = build(:candle_series, :five_minute)
      # Bullish candle (order block)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      # Middle candle
      series.add_candle(build(:candle, open: 101, high: 101.5, low: 99.5, close: 100.5))
      # Bearish impulse (breaks below middle candle low)
      series.add_candle(build(:candle, open: 100.5, high: 101, low: 97, close: 98))

      detector = described_class.new(series)
      bearish_ob = detector.bearish

      expect(bearish_ob).not_to be_nil
      expect(bearish_ob.bullish?).to be(true)
      expect(bearish_ob.close).to eq(101)
    end

    it 'returns nil when impulse candle is not preceded by bullish candle' do
      series = build(:candle_series, :five_minute)
      # Bearish candle (not an order block)
      series.add_candle(build(:candle, open: 105, high: 106, low: 104, close: 104.5))
      # Bearish impulse
      series.add_candle(build(:candle, open: 104.5, high: 105, low: 97, close: 98))

      detector = described_class.new(series)
      expect(detector.bearish).to be_nil
    end
  end

  describe '#to_h' do
    it 'serializes bullish order block' do
      series = build(:candle_series, :five_minute)
      timestamp = Time.zone.now
      series.add_candle(build(:candle, open: 105, high: 106, low: 104, close: 104.5, timestamp: timestamp))
      series.add_candle(build(:candle, open: 104.5, high: 105, low: 104, close: 104.8))
      series.add_candle(build(:candle, open: 104.8, high: 108, low: 104, close: 107))

      detector = described_class.new(series)
      result = detector.to_h

      expect(result[:bullish]).not_to be_nil
      expect(result[:bullish][:open]).to eq(105)
      expect(result[:bullish][:high]).to eq(106)
      expect(result[:bullish][:low]).to eq(104)
      expect(result[:bullish][:close]).to eq(104.5)
      expect(result[:bearish]).to be_nil
    end

    it 'serializes bearish order block' do
      series = build(:candle_series, :five_minute)
      timestamp = Time.zone.now
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101, timestamp: timestamp))
      series.add_candle(build(:candle, open: 101, high: 101.5, low: 99.5, close: 100.5))
      series.add_candle(build(:candle, open: 100.5, high: 101, low: 97, close: 98))

      detector = described_class.new(series)
      result = detector.to_h

      expect(result[:bearish]).not_to be_nil
      expect(result[:bearish][:open]).to eq(100)
      expect(result[:bearish][:high]).to eq(102)
      expect(result[:bearish][:low]).to eq(99)
      expect(result[:bearish][:close]).to eq(101)
      expect(result[:bullish]).to be_nil
    end

    it 'returns nil for both when no order blocks found' do
      series = build(:candle_series, :five_minute)
      series.add_candle(build(:candle, open: 100, high: 102, low: 99, close: 101))
      series.add_candle(build(:candle, open: 101, high: 103, low: 100, close: 102))

      detector = described_class.new(series)
      result = detector.to_h

      expect(result[:bullish]).to be_nil
      expect(result[:bearish]).to be_nil
    end
  end
end

