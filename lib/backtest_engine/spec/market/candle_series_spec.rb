# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe BacktestEngine::Market::CandleSeries do
  def candle(ts, close: 100.0, volume: 0)
    BacktestEngine::Market::Candle.new(
      timestamp: ts,
      open: close,
      high: close,
      low: close,
      close: close,
      volume: volume
    )
  end

  describe "#volume_ratio" do
    def candle(ts, vol)
      BacktestEngine::Market::Candle.new(
        timestamp: ts, open: 100, high: 101, low: 99, close: 100, volume: vol
      )
    end

    let(:t0) { Time.parse("2025-01-02 09:15:00") }
    let(:candles) do
      Array.new(15) { |i| candle(t0 + (i * 60), 100) } + [candle(t0 + (15 * 60), 200)]
    end
    let(:series) { described_class.new(candles) }

    it "returns current volume divided by rolling average" do
      # candle at index 15 has volume 200; prior 10 all have volume 100 → ratio = 2.0
      expect(series.volume_ratio(15, period: 10)).to be_within(0.01).of(2.0)
    end

    it "returns 1.0 when index is less than period" do
      expect(series.volume_ratio(5, period: 10)).to eq(1.0)
    end

    it "returns 1.0 when all volume in window is zero" do
      zero_candles = Array.new(15) { |i| candle(t0 + (i * 60), 0) } + [candle(t0 + (15 * 60), 0)]
      zero_series = described_class.new(zero_candles)
      expect(zero_series.volume_ratio(15, period: 10)).to eq(1.0)
    end
  end
  describe "basic access and indicators" do
    let(:basic_candles) do
      [
        BacktestEngine::Market::Candle.new(
          timestamp: Time.at(1),
          open: 100, high: 105, low: 99, close: 104, volume: 10
        ),
        BacktestEngine::Market::Candle.new(
          timestamp: Time.at(2),
          open: 104, high: 108, low: 103, close: 107, volume: 15
        ),
        BacktestEngine::Market::Candle.new(
          timestamp: Time.at(3),
          open: 107, high: 110, low: 106, close: 109, volume: 20
        )
      ]
    end

    subject(:series) { described_class.new(basic_candles) }

    it "exposes candles and size" do
      expect(series.size).to eq(3)
      expect(series.last).to be_a(BacktestEngine::Market::Candle)
    end

    it "computes ema without raising errors" do
      expect(series.ema(2).size).to eq(3)
    end

    it "detects structure array" do
      expect(series.structure).to all(satisfy { |val| %i[bullish bearish range].include?(val) })
    end
  end
end

