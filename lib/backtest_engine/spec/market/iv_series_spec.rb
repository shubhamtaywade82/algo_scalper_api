require "spec_helper"

RSpec.describe BacktestEngine::Market::IvSeries do
  let(:t0) { Time.parse("2025-01-02 09:15:00") }
  let(:candles) do
    10.times.map do |i|
      { timestamp: t0 + i * 60, iv: 20.0 + i }
    end
  end
  let(:series) { described_class.new(candles) }

  describe "#readings_before" do
    it "returns last n IV floats strictly before the given timestamp" do
      result = series.readings_before(t0 + 5 * 60, 3)
      expect(result).to eq([22.0, 23.0, 24.0])
    end

    it "returns empty array when no readings exist before timestamp" do
      result = series.readings_before(t0, 3)
      expect(result).to eq([])
    end

    it "returns fewer than n when not enough readings exist" do
      result = series.readings_before(t0 + 2 * 60, 5)
      expect(result.size).to be < 5
    end

    it "works with integer timestamps" do
      result = series.readings_before((t0 + 5 * 60).to_i, 3)
      expect(result).to eq([22.0, 23.0, 24.0])
    end
  end
end
