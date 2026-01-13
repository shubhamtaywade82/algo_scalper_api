# frozen_string_literal: true

module Avrz
  # AVRZ (Absorption + Volume Rejection Zone) detector.
  #
  # IMPORTANT:
  # - This is an LTF timing confirm ONLY.
  # - Do not use this for HTF/MTF bias.
  # - Accepts CandleSeries (read-only) and returns boolean.
  class Detector
    DEFAULT_LOOKBACK = 20
    DEFAULT_MIN_WICK_RATIO = 1.8
    DEFAULT_MIN_VOL_MULTIPLIER = 1.5

    def initialize(series, lookback: DEFAULT_LOOKBACK, min_wick_ratio: DEFAULT_MIN_WICK_RATIO,
                   min_vol_multiplier: DEFAULT_MIN_VOL_MULTIPLIER)
      @series = series
      @lookback = lookback.to_i
      @min_wick_ratio = min_wick_ratio.to_f
      @min_vol_multiplier = min_vol_multiplier.to_f
    end

    # Returns true when the latest candle shows rejection with relative volume.
    # This is intentionally conservative and purely candle-derived.
    def rejection?
      candle = candles.last
      return false unless candle

      recent = candles.last(@lookback)
      return false if recent.size < 5

      avg_vol = avg_volume(recent[0..-2])
      return false unless avg_vol.positive?

      vol_ok = candle.volume.to_f >= (avg_vol * @min_vol_multiplier)
      wick_ok = wick_ratio(candle) >= @min_wick_ratio
      rejection_close_ok = rejects_extreme?(candle)

      vol_ok && wick_ok && rejection_close_ok
    rescue StandardError => e
      Rails.logger.error("[Avrz::Detector] #{e.class} - #{e.message}")
      false
    end

    def to_h
      {
        rejection: rejection?,
        lookback: @lookback,
        min_wick_ratio: @min_wick_ratio,
        min_vol_multiplier: @min_vol_multiplier
      }
    end

    private

    def candles
      @series&.candles || []
    end

    def avg_volume(items)
      vols = items.map { |c| c.volume.to_f }.select(&:positive?)
      return 0.0 if vols.empty?

      vols.sum / vols.size
    end

    def wick_ratio(candle)
      body = (candle.close - candle.open).abs
      range = (candle.high - candle.low).abs
      return 0.0 if range.zero?

      upper_wick = candle.high - [candle.open, candle.close].max
      lower_wick = [candle.open, candle.close].min - candle.low
      wick = [upper_wick, lower_wick].max

      body = 0.01 if body.zero? # avoid division by zero; treat as doji
      wick / body.to_f
    end

    def rejects_extreme?(candle)
      mid = (candle.high + candle.low) / 2.0
      return false unless mid.finite?

      # A rejection candle should close away from the extreme it probed.
      if (candle.close - candle.open).positive?
        # Bullish close: reject lower side (close above mid)
        candle.close > mid
      else
        # Bearish close: reject upper side (close below mid)
        candle.close < mid
      end
    end
  end
end
