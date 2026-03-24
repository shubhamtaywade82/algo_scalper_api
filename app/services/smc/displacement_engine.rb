# frozen_string_literal: true

module Smc
  # Body vs ATR displacement filter (no indicator gem — raw OHLC math only).
  class DisplacementEngine
    Result = Struct.new(
      :bullish, :bearish, :range, :atr, :body, :upper_wick, :lower_wick
    )

    def initialize(series, atr_period: 14, body_atr_mult: 1.2, max_wick_body_ratio: 0.5)
      @series = series
      @atr_period = atr_period
      @body_atr_mult = body_atr_mult
      @max_wick_body_ratio = max_wick_body_ratio
    end

    def call
      bars = @series&.candles || []
      return empty_result if bars.size < 2

      c = bars.last
      prev = bars.last(@atr_period + 1)
      return empty_result if prev.size < 2

      atr = average_tr(prev)
      body = (c.close - c.open).abs
      upper_wick = c.high - [c.open, c.close].max
      lower_wick = [c.open, c.close].min - c.low
      range = c.high - c.low

      bullish = c.close > c.open &&
                body >= atr * @body_atr_mult &&
                wick_ok?(upper_wick, body)

      bearish = c.open > c.close &&
                body >= atr * @body_atr_mult &&
                wick_ok?(lower_wick, body)

      Result.new(
        bullish: bullish,
        bearish: bearish,
        range: range,
        atr: atr,
        body: body,
        upper_wick: upper_wick,
        lower_wick: lower_wick
      )
    end

    private

    def empty_result
      Result.new(bullish: false, bearish: false, range: 0.0, atr: 0.0, body: 0.0,
                 upper_wick: 0.0, lower_wick: 0.0)
    end

    def average_tr(prev)
      trs = prev.each_cons(2).map do |a, b|
        [(b.high - b.low), (b.high - a.close).abs, (b.low - a.close).abs].max
      end
      slice = trs.last(@atr_period)
      slice.sum / slice.size.to_f
    end

    def wick_ok?(wick, body)
      return true if body <= 1e-9

      wick / body.to_f <= @max_wick_body_ratio
    end
  end
end
