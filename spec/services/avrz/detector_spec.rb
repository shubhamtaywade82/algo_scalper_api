# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Avrz::Detector do
  describe '#rejection?' do
    it 'returns true for a high-volume rejection candle' do
      series = build(:candle_series, :five_minute)

      10.times do |i|
        series.add_candle(
          build(
            :candle,
            timestamp: (20 - i).minutes.ago,
            open: 100,
            high: 102,
            low: 99,
            close: 101,
            volume: 100
          )
        )
      end

      # Long lower wick + bullish close + high volume
      series.add_candle(
        build(
          :candle,
          timestamp: 1.minute.ago,
          open: 100,
          high: 101,
          low: 90,
          close: 100.5,
          volume: 1000
        )
      )

      detector = described_class.new(series, lookback: 10, min_wick_ratio: 1.5, min_vol_multiplier: 2.0)
      expect(detector.rejection?).to be(true)
    end

    it 'returns false when volume is too low' do
      series = build(:candle_series, :five_minute)

      10.times do |i|
        series.add_candle(
          build(
            :candle,
            timestamp: (20 - i).minutes.ago,
            open: 100,
            high: 102,
            low: 99,
            close: 101,
            volume: 100
          )
        )
      end

      # Long wick but low volume
      series.add_candle(
        build(
          :candle,
          timestamp: 1.minute.ago,
          open: 100,
          high: 101,
          low: 90,
          close: 100.5,
          volume: 150 # Below 2x average (200)
        )
      )

      detector = described_class.new(series, lookback: 10, min_wick_ratio: 1.5, min_vol_multiplier: 2.0)
      expect(detector.rejection?).to be(false)
    end

    it 'returns false when wick ratio is too low' do
      series = build(:candle_series, :five_minute)

      10.times do |i|
        series.add_candle(
          build(
            :candle,
            timestamp: (20 - i).minutes.ago,
            open: 100,
            high: 102,
            low: 99,
            close: 101,
            volume: 100
          )
        )
      end

      # High volume but small wick
      series.add_candle(
        build(
          :candle,
          timestamp: 1.minute.ago,
          open: 100,
          high: 101,
          low: 99.5,
          close: 100.5,
          volume: 1000
        )
      )

      detector = described_class.new(series, lookback: 10, min_wick_ratio: 1.5, min_vol_multiplier: 2.0)
      expect(detector.rejection?).to be(false)
    end

    it 'returns false when there are not enough candles' do
      series = build(:candle_series, :five_minute)

      3.times do |i|
        series.add_candle(
          build(
            :candle,
            timestamp: (10 - i).minutes.ago,
            open: 100,
            high: 102,
            low: 99,
            close: 101,
            volume: 100
          )
        )
      end

      detector = described_class.new(series, lookback: 10, min_wick_ratio: 1.5, min_vol_multiplier: 2.0)
      expect(detector.rejection?).to be(false)
    end

    it 'returns false when candle does not reject extreme' do
      series = build(:candle_series, :five_minute)

      10.times do |i|
        series.add_candle(
          build(
            :candle,
            timestamp: (20 - i).minutes.ago,
            open: 100,
            high: 102,
            low: 99,
            close: 101,
            volume: 100
          )
        )
      end

      # High volume, long wick, but closes at extreme (not rejection)
      series.add_candle(
        build(
          :candle,
          timestamp: 1.minute.ago,
          open: 100,
          high: 101,
          low: 90,
          close: 90.5, # Closes near low (not rejecting)
          volume: 1000
        )
      )

      detector = described_class.new(series, lookback: 10, min_wick_ratio: 1.5, min_vol_multiplier: 2.0)
      expect(detector.rejection?).to be(false)
    end
  end

  describe '#to_h' do
    it 'serializes detector configuration and state' do
      series = build(:candle_series, :five_minute)
      10.times do |i|
        series.add_candle(
          build(
            :candle,
            timestamp: (20 - i).minutes.ago,
            open: 100,
            high: 102,
            low: 99,
            close: 101,
            volume: 100
          )
        )
      end

      detector = described_class.new(series, lookback: 20, min_wick_ratio: 1.8, min_vol_multiplier: 1.5)
      result = detector.to_h

      expect(result).to have_key(:rejection)
      expect(result).to have_key(:lookback)
      expect(result).to have_key(:min_wick_ratio)
      expect(result).to have_key(:min_vol_multiplier)
      expect(result[:lookback]).to eq(20)
      expect(result[:min_wick_ratio]).to eq(1.8)
      expect(result[:min_vol_multiplier]).to eq(1.5)
    end
  end
end
