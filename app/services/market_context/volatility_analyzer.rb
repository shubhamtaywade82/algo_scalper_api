# frozen_string_literal: true

module MarketContext
  # Maps realized volatility (ATR vs typical range) to coarse states.
  class VolatilityAnalyzer
    Result = Struct.new(:state, :atr, :range_ratio, keyword_init: true) # rubocop:disable Style/RedundantStructKeywordInit

    HIGH_MULT = 1.5
    LOW_MULT = 0.7
    EXHAUSTED_MULT = 2.2

    def initialize(series:)
      @series = series
    end

    def call
      candles = @series.candles
      return Result.new(state: :normal, atr: nil, range_ratio: nil) if candles.size < 3

      @series.ensure_sorted!
      atr = @series.atr(14)
      ranges = candles.last([candles.size, 20].min).map { |c| c.high.to_f - c.low.to_f }
      avg_range = ranges.sum / ranges.size.to_f
      current = candles.last
      last_range = current.high.to_f - current.low.to_f

      ratio = avg_range.positive? ? (last_range / avg_range) : 1.0
      atr_f = atr&.to_f

      state = classify(atr_f, avg_range, ratio, last_range, current.close.to_f)

      Result.new(state: state, atr: atr_f, range_ratio: ratio.round(4))
    end

    private

    def classify(atr_f, avg_range, ratio, last_range, close_px)
      ref = if atr_f&.positive? && close_px.positive?
              atr_f / close_px
            elsif avg_range.positive? && close_px.positive?
              (avg_range / close_px)
            else
              0.0
            end

      return :exhausted_high if ratio >= EXHAUSTED_MULT && ref > 0.012
      return :high if ratio >= HIGH_MULT || ref > 0.01
      return :low if ratio <= LOW_MULT && ref < 0.004

      :normal
    end
  end
end
