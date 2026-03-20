# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::ATRUtils do
  let(:series) { CandleSeries.new(symbol: 'NIFTY', interval: '5') }

  describe '.calculate_atr' do
    it 'calculates ATR for a window of candles' do
      # Create some mock candles
      15.times do |i|
        candle = build(:candle, timestamp: i.minutes.ago, high: 25_100, low: 24_900, close: 25_000)
        series.add_candle(candle)
      end

      bars = series.candles
      atr = described_class.calculate_atr(bars)

      expect(atr).to be_a(Float)
      expect(atr).to be > 0
    end

    it 'returns nil for insufficient data' do
      bars = [build(:candle)]
      atr = described_class.calculate_atr(bars)

      expect(atr).to be_nil
    end
  end

  describe '.atr_downtrend?' do
    before do
      # First window: higher volatility
      30.times do |i|
        candle = build(:candle, timestamp: i.minutes.ago, high: 25_200 + (i * 10), low: 24_800 - (i * 10),
                                close: 25_000 + (i * 5))
        series.add_candle(candle)
      end
    end

    it 'detects ATR downtrend when last 3 windows show decreasing ATR' do
      bars = series.candles

      # Mock CandleSeries to return decreasing ATR values
      # We need at least (bars.size - period) values. Bars size is 30, period is 14, so 16 values.
      counter = 0
      values = [100.0, 95.0, 90.0, 85.0, 80.0, 75.0, 70.0, 65.0, 60.0, 55.0, 50.0, 45.0, 40.0, 35.0, 30.0, 25.0]
      allow_any_instance_of(CandleSeries).to receive(:atr) do
        val = values[counter]
        counter += 1
        val
      end

      result = described_class.atr_downtrend?(bars, period: 14)

      expect(result).to be true
    end

    it 'returns false when ATR is not trending down' do
      bars = series.candles

      # Mock CandleSeries to return increasing ATR values
      counter = 0
      values = [25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 100.0]
      allow_any_instance_of(CandleSeries).to receive(:atr) do
        val = values[counter]
        counter += 1
        val
      end

      result = described_class.atr_downtrend?(bars, period: 14)

      expect(result).to be false
    end

    it 'returns false when bars has insufficient data' do
      bars = series.candles.first(10)
      result = described_class.atr_downtrend?(bars, period: 14)

      expect(result).to be false
    end
  end

  describe '.atr_ratio' do
    it 'calculates ATR ratio between current and historical windows' do
      # Create 40 candles to be safe
      40.times do |i|
        candle = build(:candle, timestamp: i.minutes.ago, high: 25_100, low: 24_900, close: 25_000)
        series.add_candle(candle)
      end

      bars = series.candles
      # calculate_atr(14) needs 15 candles
      ratio = described_class.atr_ratio(bars, current_period: 15, historical_period: 15)

      expect(ratio).to be_a(Float)
      expect(ratio).to be > 0
    end

    it 'returns nil when data is insufficient for ratio' do
      bars = series.candles.first(10)
      ratio = described_class.atr_ratio(bars, current_period: 14, historical_period: 7)

      expect(ratio).to be_nil
    end
  end
end
