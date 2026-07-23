# frozen_string_literal: true

# SMC / ICT / Price Action Confluence Strategy for Option Backtesting.
# Uses Order Blocks, Fair Value Gaps, and Premium/Discount Zones.
class SmcIctOptionBacktestStrategy
  def initialize(series:)
    @series = series
  end

  def generate_signal(index)
    # Prefix-slice the series up to the current bar to prevent look-ahead bias
    prefix_series = build_prefix_series(index)
    return nil if prefix_series.candles.size < 30

    # 1. Detect Order Blocks
    ob_detector = Smc::Detectors::OrderBlocks.new(prefix_series)
    active_obs = ob_detector.active_blocks

    # 2. Detect Fair Value Gaps
    fvg_detector = Smc::Detectors::Fvg.new(prefix_series)
    active_fvgs = fvg_detector.active_gaps

    # 3. Detect Premium / Discount zones
    pd_detector = Smc::Detectors::PremiumDiscount.new(prefix_series)
    is_premium = pd_detector.premium?
    is_discount = pd_detector.discount?

    current_price = prefix_series.candles.last.close

    # Bullish Setup:
    # - Price is in Discount zone
    # - Active Bullish Order Block exists
    # - Active Bullish FVG exists near/overlapping the OB high
    # - Price pulls back near/into the OB high range
    bull_ob = active_obs.reverse.find { |ob| ob[:bias] == :bullish }
    if bull_ob && is_discount
      ob_height = bull_ob[:high] - bull_ob[:low]
      threshold = [ob_height * 2.0, bull_ob[:high] * 0.005].max

      has_fvg = active_fvgs.any? do |fvg|
        fvg[:type] == :bullish && (fvg[:from] - bull_ob[:high]).abs <= threshold
      end

      if has_fvg && current_price <= bull_ob[:high] + threshold && current_price >= bull_ob[:low] - (bull_ob[:low] * 0.002)
        return { type: :ce, price: current_price, reason: 'bull_ob_fvg_confluence' }
      end
    end

    # Bearish Setup:
    # - Price is in Premium zone
    # - Active Bearish Order Block exists
    # - Active Bearish FVG exists near/overlapping the OB low
    # - Price pulls back near/into the OB low range
    bear_ob = active_obs.reverse.find { |ob| ob[:bias] == :bearish }
    if bear_ob && is_premium
      ob_height = bear_ob[:high] - bear_ob[:low]
      threshold = [ob_height * 2.0, bear_ob[:low] * 0.005].max

      has_fvg = active_fvgs.any? do |fvg|
        fvg[:type] == :bearish && (fvg[:to] - bear_ob[:low]).abs <= threshold
      end

      if has_fvg && current_price >= bear_ob[:low] - threshold && current_price <= bear_ob[:high] + (bear_ob[:high] * 0.002)
        return { type: :pe, price: current_price, reason: 'bear_ob_fvg_confluence' }
      end
    end

    nil
  end

  private

  def build_prefix_series(end_index)
    subset = @series.candles[0..end_index]
    s = CandleSeries.new(symbol: @series.symbol, interval: @series.interval)
    subset.each { |c| s.candles << c }
    s
  end
end
