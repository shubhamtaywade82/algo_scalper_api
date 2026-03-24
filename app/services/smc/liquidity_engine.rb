# frozen_string_literal: true

module Smc
  # Tight liquidity sweep detector (wick beyond prior window extreme, close reclaimed).
  class LiquidityEngine
    Event = Struct.new(:type, :level, :strength)

    def initialize(series, lookback: 7, close_reclaim: true)
      @series = series
      @lookback = lookback
      @close_reclaim = close_reclaim
    end

    def call
      bars = @series&.candles || []
      return nil if bars.size < @lookback + 1

      window = bars.last(@lookback)
      last = window.last
      body = window[0..-2]
      return nil if body.empty?

      prev_high = body.map(&:high).max
      prev_low = body.map(&:low).min

      if last.high > prev_high && reclaim_high?(last, prev_high)
        return Event.new(
          type: :sweep_high,
          level: prev_high,
          strength: last.high - prev_high
        )
      end

      if last.low < prev_low && reclaim_low?(last, prev_low)
        return Event.new(
          type: :sweep_low,
          level: prev_low,
          strength: prev_low - last.low
        )
      end

      nil
    end

    private

    def reclaim_high?(last, prev_high)
      !@close_reclaim || last.close < prev_high
    end

    def reclaim_low?(last, prev_low)
      !@close_reclaim || last.close > prev_low
    end
  end
end
