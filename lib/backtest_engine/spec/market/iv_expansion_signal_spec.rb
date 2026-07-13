require "spec_helper"
require "time"

RSpec.describe BacktestEngine::Market::IvExpansionSignal do
  let(:t0) { Time.parse("2025-01-02 09:15:00") }

  def make_series(iv_values)
    candles = iv_values.each_with_index.map do |iv, i|
      { timestamp: t0 + i * 60, iv: iv.to_f }
    end
    BacktestEngine::Market::IvSeries.new(candles)
  end

  describe "#modifier_at" do
    context "when fewer than period readings exist before timestamp" do
      it "returns 0.0" do
        series = make_series([20.0, 21.0, 22.0])
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 2 * 60)).to eq(0.0)
      end
    end

    context "when no readings exist before timestamp" do
      it "returns 0.0" do
        series = make_series([20.0])
        signal = described_class.new(series, period: 3)
        expect(signal.modifier_at(t0)).to eq(0.0)
      end
    end

    context "when current IV is higher than rolling average" do
      it "returns a positive modifier" do
        # 10 readings at 20.0, then current at 22.0 → delta = +10%
        iv_values = Array.new(10, 20.0) + [22.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        result = signal.modifier_at(t0 + 10 * 60)
        expect(result).to be_within(0.01).of(10.0)
      end
    end

    context "when current IV is lower than rolling average" do
      it "returns a negative modifier" do
        iv_values = Array.new(10, 20.0) + [18.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        result = signal.modifier_at(t0 + 10 * 60)
        expect(result).to be_within(0.01).of(-10.0)
      end
    end

    context "when iv_series is nil" do
      it "returns 0.0" do
        signal = described_class.new(nil)
        expect(signal.modifier_at(t0)).to eq(0.0)
      end
    end

    context "when IV expansion is extreme positive" do
      it "clamps at +15.0" do
        iv_values = Array.new(10, 10.0) + [100.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 10 * 60)).to eq(15.0)
      end
    end

    context "when IV expansion is extreme negative" do
      it "clamps at -15.0" do
        iv_values = Array.new(10, 100.0) + [1.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 10 * 60)).to eq(-15.0)
      end
    end

    context "with integer timestamps" do
      it "handles integer timestamps correctly" do
        iv_values = Array.new(10, 20.0) + [22.0]
        series = make_series(iv_values)
        signal = described_class.new(series, period: 10)
        result = signal.modifier_at((t0 + 10 * 60).to_i)
        expect(result).to be > 0
      end
    end

    context "when rolling average is zero" do
      it "returns 0.0" do
        candles = 10.times.map { |i| { timestamp: t0 + i * 60, iv: 0.0 } } +
                  [{ timestamp: t0 + 10 * 60, iv: 20.0 }]
        series = BacktestEngine::Market::IvSeries.new(candles)
        signal = described_class.new(series, period: 10)
        expect(signal.modifier_at(t0 + 10 * 60)).to eq(0.0)
      end
    end
  end
end
