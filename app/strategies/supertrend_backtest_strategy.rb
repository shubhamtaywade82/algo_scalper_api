# frozen_string_literal: true

# Minimal backtest strategy: Supertrend direction only.
class SupertrendBacktestStrategy
  def initialize(series:, supertrend_cfg: {})
    @series = series
    @supertrend_cfg = supertrend_cfg
  end

  def generate_signal(_index = nil)
    st = Indicators::Supertrend.new(series: @series, **@supertrend_cfg).call
    direction = SupertrendTrend.direction(series: @series, supertrend_result: st)
    return nil if direction == :none

    { direction: direction == :long ? :buy : :sell, price: @series.candles.last.close }
  end
end
