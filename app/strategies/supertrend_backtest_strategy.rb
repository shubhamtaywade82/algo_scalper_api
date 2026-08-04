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

    if @series.respond_to?(:adx)
      adx = @series.adx(14)
      return nil if adx.nil? || adx < @adx_min
    end

    if @series_5m.present?
      st_5m = Indicators::Supertrend.new(series: @series_5m, **@supertrend_cfg).call
      dir_5m = SupertrendTrend.direction(series: @series_5m, supertrend_result: st_5m)
      return nil unless dir_1m == dir_5m
    end

    { type: dir_1m == :long ? :ce : :pe, price: @series.candles.last.close }
  end
end

