# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe BacktestEngine::Market::RegimeScorer do
  def candle(ts, o, h, l, c)
    BacktestEngine::Market::Candle.new(timestamp: ts, open: o, high: h, low: l, close: c, volume: 1000)
  end

  let(:t0) { Time.parse("2025-01-02 09:15:00") }
  let(:candles) do
    25.times.map { |i| candle(t0 + i * 60, 100 + i, 101 + i, 99 + i, 100 + i) }
  end
  let(:series) { BacktestEngine::Market::CandleSeries.new(candles) }

  describe "#score_at" do
    it "returns hash with score and direction" do
      scorer = described_class.new(series)
      result = scorer.score_at(21)

      expect(result).to include(:score, :direction)
      expect(result[:score]).to be_between(0, 100)
      expect(%i[bullish bearish range]).to include(result[:direction])
    end

    it "returns neutral for early index" do
      scorer = described_class.new(series)
      result = scorer.score_at(5)

      expect(result[:score]).to eq(50)
      expect(result[:direction]).to eq(:range)
    end
  end
end
