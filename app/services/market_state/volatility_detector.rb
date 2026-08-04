# frozen_string_literal: true

module MarketState
  # Lean volatility detector based on ATR expansion
  class VolatilityDetector
    def self.expanding?(series)
      return false if series.candles.size < 16

      # Use the latest ATR value compared to the previous one
      series.atr(14)

      # We need history to check expansion
      # CandleSeries#atr returns a single value (latest)
      # We need to manually calculate or check if ATR is rising

      hlc = series.hlc
      atr_series = TechnicalAnalysis::Atr.calculate(hlc, period: 14)
      return false if atr_series.size < 2

      atr_series[-1].atr > atr_series[-2].atr
    end
  end
end
