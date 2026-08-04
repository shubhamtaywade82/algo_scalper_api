# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::ATRUtils do
  let(:series) { build(:candle_series, symbol: 'NIFTY', interval: '1') }

  describe '.calculate_atr' do
    before do
      # Add enough candles for ATR calculation (needs at least 14)
      15.times do |i|
        candle = build(:candle, timestamp: i.minutes.ago, high: 25_100 + i, low: 24_900 - i, close: 25_000 + i)
        series.add_candle(candle)
      end
    end

    it 'calculates ATR using CandleSeries' do
      bars = series.candles

      atr = described_class.calculate_atr(bars)

      expect(atr).to be_a(Numeric)
      expect(atr).to be > 0
    end

    it 'returns nil when bars is nil' do
      atr = described_class.calculate_atr(nil)

      expect(atr).to be_nil
    end

    it 'returns nil when bars is empty' do
      atr = described_class.calculate_atr([])

      expect(atr).to be_nil
    end

    it 'returns nil when bars has less than 2 candles' do
      bars = [build(:candle)]

      atr = described_class.calculate_atr(bars)

      expect(atr).to be_nil
    end
  end

  describe '.atr_downtrend?' do
    before do
      # Create series with decreasing ATR
      # First window: higher volatility
      20.times do |i|
        candle = build(:candle, timestamp: i.minutes.ago, high: 25_200 + (i * 10), low: 24_800 - (i * 10),
                                close: 25_000 + (i * 5))
        series.add_candle(candle)
      end
    end

    it 'detects ATR downtrend when last 3 windows show decreasing ATR' do
      bars = series.candles

      # Mock CandleSeries to return decreasing ATR values
      allow_any_instance_of(CandleSeries).to receive(:atr).and_return(100.0, 90.0, 80.0, 70.0)

      result = described_class.atr_downtrend?(bars, period: 14)

      expect(result).to be true
    end

    it 'returns false when ATR is not trending down' do
      bars = series.candles

      # Mock CandleSeries to return increasing ATR values
      allow_any_instance_of(CandleSeries).to receive(:atr).and_return(70.0, 80.0, 90.0, 100.0)

      result = described_class.atr_downtrend?(bars, period: 14)

      expect(result).to be false
    end

    it 'returns false when bars has insufficient data' do
      bars = Array.new(10) { build(:candle) }

      result = described_class.atr_downtrend?(bars, period: 14)

      expect(result).to be false
    end

    it 'returns false when bars is nil' do
      result = described_class.atr_downtrend?(nil)

      expect(result).to be false
    end

    it 'returns false when bars is empty' do
      result = described_class.atr_downtrend?([])

      expect(result).to be false
    end
  end

  describe '.atr_ratio' do
    before do
      # Add enough candles for both periods
      25.times do |i|
        candle = build(:candle, timestamp: i.minutes.ago, high: 25_100 + i, low: 24_900 - i, close: 25_000 + i)
        series.add_candle(candle)
      end
    end

    it 'calculates ratio of current ATR to historical ATR' do
      bars = series.candles

      # Mock ATR calculations
      allow(described_class).to receive(:calculate_atr).and_return(100.0, 80.0)

      ratio = described_class.atr_ratio(bars, current_period: 14, historical_period: 7)

      # Current: 100, Historical: 80, Ratio: 1.25
      expect(ratio).to be_within(0.01).of(1.25)
    end

    it 'returns nil when bars has insufficient data' do
      bars = Array.new(10) { build(:candle) }

      ratio = described_class.atr_ratio(bars, current_period: 14, historical_period: 7)

      expect(ratio).to be_nil
    end

    it 'returns nil when ATR cannot be calculated' do
      bars = series.candles

      allow(described_class).to receive(:calculate_atr).and_return(nil, 80.0)

      ratio = described_class.atr_ratio(bars, current_period: 14, historical_period: 7)

      expect(ratio).to be_nil
    end
  end
end
