# frozen_string_literal: true

module Smc
  # Premium / discount / equilibrium from recent range (50 bars).
  class ZoneEngine
    LOOKBACK = 50

    def initialize(series)
      @series = series
    end

    # @param price [Float, nil] when set, adds :location (premium/discount/equilibrium)
    def call(price: nil)
      window = (@series&.candles || []).last(LOOKBACK)
      return empty_zones(price) if window.size < 2

      highs = window.map(&:high)
      lows = window.map(&:low)
      high = highs.max
      low = lows.min
      eq = (high + low) / 2.0

      zones = {
        premium: (eq..high),
        discount: (low..eq),
        equilibrium: eq
      }
      zones[:location] = locate(price, eq) if price
      zones
    end

    private

    def empty_zones(price)
      z = { premium: nil, discount: nil, equilibrium: nil }
      z[:location] = :equilibrium if price
      z
    end

    def locate(price, eq)
      p = price.to_f
      e = eq.to_f
      return :equilibrium if (p - e).abs <= 1e-6

      p > e ? :premium : :discount
    end
  end
end
