require "spec_helper"

RSpec.describe BacktestEngine::Market::Candle do
  describe "#bullish?" do
    it "returns true when close > open" do
      candle = described_class.new(
        timestamp: Time.now,
        open: 100,
        high: 110,
        low: 95,
        close: 108
      )

      expect(candle.bullish?).to be true
      expect(candle.bearish?).to be false
    end
  end

  describe "validations" do
    it "raises when high < low" do
      expect do
        described_class.new(
          timestamp: Time.now,
          open: 100,
          high: 90,
          low: 95,
          close: 98
        )
      end.to raise_error(ArgumentError)
    end
  end
end

