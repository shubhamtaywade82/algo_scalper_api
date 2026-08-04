# frozen_string_literal: true

require "spec_helper"

RSpec.describe BacktestEngine::Market::RegimeState do
  describe "#update" do
    it "returns stable and allowed_to_trade after stability_candles same direction" do
      state = described_class.new(stability_candles: 3, cooldown_candles: 2)

      r1 = state.update(0, :bullish)
      expect(r1[:stable]).to be false
      expect(r1[:allowed_to_trade]).to be false

      r2 = state.update(1, :bullish)
      expect(r2[:stable]).to be false

      r3 = state.update(2, :bullish)
      expect(r3[:stable]).to be true
      expect(r3[:allowed_to_trade]).to be true
    end

    it "enters cooldown after direction flip" do
      state = described_class.new(stability_candles: 2, cooldown_candles: 3)

      state.update(0, :bullish)
      state.update(1, :bullish)
      r2 = state.update(2, :bullish)
      expect(r2[:allowed_to_trade]).to be true

      state.update(3, :bearish)
      r4 = state.update(4, :bearish)
      expect(r4[:allowed_to_trade]).to be false

      state.update(5, :bearish)
      r6 = state.update(6, :bearish)
      r7 = state.update(7, :bearish)
      expect(r7[:allowed_to_trade]).to be true
    end
  end
end
