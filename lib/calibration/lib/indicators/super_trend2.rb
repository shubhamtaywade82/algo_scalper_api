# frozen_string_literal: true

module Indicators
  # Ports TradingView's ta.supertrend2 (import TradingView/ta/10)
  #
  # Key differences from standard SuperTrend:
  #   1. Wick reversals: direction flips when HIGH > upper_band (not just close)
  #      or LOW < lower_band — not just close crossover.
  #   2. Band is clamped against the previous band in the same direction,
  #      identical to the standard formulation.
  #
  # Returns array of [{ st:, direction: }] parallel to input bars.
  #   direction: -1 = bullish (price above ST), +1 = bearish (price below ST)
  #
  # @param bars [Array<Hash>] each: { high:, low:, close:, atr: }
  #   atr must already be computed externally (allows dynamic ATR length)
  # @param factor [Float] multiplier (default 2.0)
  # @param use_wicks [Boolean] wick reversal mode (default true)
  class SuperTrend2
    def initialize(factor: 2.0, use_wicks: true)
      @factor    = factor
      @use_wicks = use_wicks
    end

    # @param bars [Array<Hash>] :high, :low, :close, :atr
    # @return [Array<Hash>] :st, :direction per bar
    def calculate(bars)
      results   = []
      prev_upper = nil
      prev_lower = nil
      prev_dir   = 1      # start bearish until first real bar
      prev_st    = nil

      bars.each_with_index do |bar, i|
        hl2        = (bar[:high] + bar[:low]) / 2.0
        atr        = bar[:atr]

        raw_upper  = hl2 + @factor * atr
        raw_lower  = hl2 - @factor * atr

        # Clamp bands against previous (prevents band from widening on retrace)
        upper = if prev_upper
                  (raw_upper < prev_upper || bars[i - 1][:close] > prev_upper) ? raw_upper : prev_upper
                else
                  raw_upper
                end

        lower = if prev_lower
                  (raw_lower > prev_lower || bars[i - 1][:close] < prev_lower) ? raw_lower : prev_lower
                else
                  raw_lower
                end

        # Direction logic — wick reversal variant
        direction = if prev_dir == -1
                      # Was bullish: flip to bearish if low breaks below lower band (wick)
                      # or close crosses below lower band
                      flip_bear = @use_wicks ? bar[:low] < (prev_lower || lower) : bar[:close] < (prev_lower || lower)
                      flip_bear ? 1 : -1
                    else
                      # Was bearish: flip to bullish if high breaks above upper band (wick)
                      # or close crosses above upper band
                      flip_bull = @use_wicks ? bar[:high] > (prev_upper || upper) : bar[:close] > (prev_upper || upper)
                      flip_bull ? -1 : 1
                    end

        # ST line: lower band when bullish, upper band when bearish
        st = direction == -1 ? lower : upper

        results << { st: st, direction: direction }

        prev_upper = upper
        prev_lower = lower
        prev_dir   = direction
        prev_st    = st
      end

      results
    end
  end
end