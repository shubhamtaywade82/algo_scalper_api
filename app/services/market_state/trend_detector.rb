# frozen_string_literal: true

module MarketState
  # Lean trend detector based on market structure
  class TrendDetector
    def self.bullish?(candles)
      return false if candles.size < 2
      
      last = candles[-1]
      prev = candles[-2]

      # Price-action based break of structure (BOS)
      last.high > prev.high && last.close > prev.high
    end

    def self.bearish?(candles)
      return false if candles.size < 2
      
      last = candles[-1]
      prev = candles[-2]

      last.low < prev.low && last.close < prev.low
    end
  end
end
