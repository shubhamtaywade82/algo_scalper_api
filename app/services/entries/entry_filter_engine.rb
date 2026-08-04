# frozen_string_literal: true

module Entries
  # Institutional Entry Filter Engine for weekly index options (NIFTY/SENSEX)
  # Corrects the "indicator-only" mistake by requiring alignment of:
  # 1. Market Structure (BOS)
  # 2. Liquidity Expansion (Range Expansion)
  # 3. Volatility Expansion (ATR Rising)
  class EntryFilterEngine
    RANGE_THRESHOLD = {
      nifty: 1.4,
      sensex: 1.6,
      banknifty: 1.5
    }.freeze

    def initialize(series:, symbol:)
      @series = series
      @symbol = symbol.to_s.upcase
    end

    # Validates the entry based on institutional alignment principles
    def valid_entry?(direction:)
      # 1. Market Structure (BOS) - Primary Signal
      return false unless bos?(direction)

      # 2. Liquidity Expansion (Range > 1.5x Avg)
      return false unless range_expansion?

      # 3. Volatility Expansion (ATR Rising)
      return false unless atr_rising?

      true
    end

    private

    def bos?(direction)
      # Use BosExtractor for close-based structure breaks
      bos = Entries::BosExtractor.last_confirmed_bos(@series)
      if bos
        return bos[:direction] == direction
      end

      # Fallback to simple high/low break as per institutional model
      last = @series.candles[-1]
      prev = @series.candles[-2]
      return false unless last && prev

      if direction == :bullish
        last.high > prev.high
      else
        last.low < prev.low
      end
    end

    def range_expansion?
      return false if @series.candles.size < 21

      last_candle = @series.candles[-1]
      last_range = last_candle.high - last_candle.low
      
      # avg_range_20 (excluding the current candle)
      avg_range = @series.candles.last(21).first(20).map { |c| c.high - c.low }.sum / 20.0
      return false if avg_range.zero?

      (last_range / avg_range) > threshold
    end

    def atr_rising?
      # Need at least 15 candles for ATR(14)
      return false if @series.candles.size < 16

      hlc = @series.hlc
      atr_series = TechnicalAnalysis::Atr.calculate(hlc, period: 14)
      return false if atr_series.size < 2

      # Check if ATR is expanding
      atr_series[-1].atr > atr_series[-2].atr
    end

    def threshold
      if @symbol.include?('SENSEX')
        RANGE_THRESHOLD[:sensex]
      elsif @symbol.include?('BANKNIFTY')
        RANGE_THRESHOLD[:banknifty]
      else
        RANGE_THRESHOLD[:nifty]
      end
    end
  end
end
