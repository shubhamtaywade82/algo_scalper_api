# frozen_string_literal: true

# Minimal backtest strategy: Supertrend direction only.
#
# Signal at bar +index+ is computed from a PREFIX series (candles 0..index)
# so the trend is only ever known as of that bar — the full-series form
# leaked the final trend into every historical entry (lookahead bias).
class SupertrendBacktestStrategy
  def initialize(series:, supertrend_cfg: {})
    @series = series
    @supertrend_cfg = supertrend_cfg
  end

  def generate_signal(index = nil)
    series = series_upto(index)

    st = Indicators::Supertrend.new(series: series, **@supertrend_cfg).call
    direction = SupertrendTrend.direction(series: series, supertrend_result: st)
    return nil if direction == :none

    { direction: direction == :long ? :buy : :sell, price: series.candles.last.close }
  end

  private

  # Prefix view of the series as of +index+ (inclusive). +nil+ or an
  # out-of-range index means "everything currently visible".
  def series_upto(index)
    return @series if index.nil?

    last = index.clamp(0, @series.candles.size - 1)
    return @series if last >= @series.candles.size - 1

    CandleSeries.new(symbol: @series.symbol, interval: @series.interval).tap do |copy|
      @series.candles[0..last].each { |c| copy.candles << c }
    end
  end
end
