# frozen_string_literal: true

# Supertrend + ADX Multi-Timeframe backtest strategy.
class SupertrendBacktestStrategy
  def initialize(series:, supertrend_cfg: {}, series_5m: nil, adx_min: 20.0)
    @series = series
    @supertrend_cfg = supertrend_cfg
    @series_5m = series_5m
    @adx_min = adx_min
  end

  def generate_signal(_index = nil)
    st_1m = Indicators::Supertrend.new(series: @series, **@supertrend_cfg).call
    dir_1m = SupertrendTrend.direction(series: @series, supertrend_result: st_1m)
    return nil if dir_1m == :none

    { type: direction == :long ? :ce : :pe, price: @series.candles.last.close }
  end
end

