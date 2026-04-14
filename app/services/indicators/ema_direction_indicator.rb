# frozen_string_literal: true

module Indicators
  # EMA 9/21 cross direction indicator.
  #
  # Returns { direction: :bullish | :bearish | :neutral, fast: Float, slow: Float,
  #           aligned: Boolean, spread_pct: Float }
  #
  # Used in Signal::Engine as a tie-breaking direction confirm:
  #   - If Supertrend says bullish but EMA says bearish → require ADX >= 25
  #   - If both agree → normal ADX threshold
  class EmaDirectionIndicator
    DEFAULT_FAST = 9
    DEFAULT_SLOW = 21

    def initialize(series:, config: {})
      @series      = series
      @fast_period = config.fetch(:fast_period, DEFAULT_FAST).to_i
      @slow_period = config.fetch(:slow_period, DEFAULT_SLOW).to_i
    end

    def calculate
      closes = @series.candles.map { |c| c.close.to_f }
      return neutral_result if closes.size < @slow_period

      fast_val = ema(closes, @fast_period)
      slow_val = ema(closes, @slow_period)
      return neutral_result if fast_val.nil? || slow_val.nil?

      direction = if fast_val > slow_val then :bullish
                  elsif fast_val < slow_val then :bearish
                  else :neutral
                  end

      spread_pct = slow_val.positive? ? ((fast_val - slow_val).abs / slow_val * 100).round(4) : 0.0

      { direction: direction, fast: fast_val.round(4), slow: slow_val.round(4),
        aligned: direction != :neutral, spread_pct: spread_pct }
    end

    private

    # Standard EMA: k = 2 / (period + 1)
    def ema(closes, period)
      return nil if closes.size < period

      k    = 2.0 / (period + 1)
      seed = closes.first(period).sum / period.to_f

      closes.drop(period).reduce(seed) { |prev, c| (c * k) + (prev * (1 - k)) }
    end

    def neutral_result
      { direction: :neutral, fast: nil, slow: nil, aligned: false, spread_pct: 0.0 }
    end
  end
end
