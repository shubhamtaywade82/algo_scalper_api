# frozen_string_literal: true

module MarketContext
  # Price-structure hints from recent candles + VWAP (session cumulative on series).
  class StructureAnalyzer
    Result = Struct.new(:trend, :strength, :displacement, :vwap_behavior, keyword_init: true) # rubocop:disable Style/RedundantStructKeywordInit

    LOOKBACK = 5
    DISPLACE_BODY_MULT = 1.5
    DISPLACE_VOL_MULT = 1.5
    CHOP_CROSS_MIN = 3

    def initialize(series:)
      @series = series
    end

    def call
      candles = @series.candles
      return default_result if candles.size < LOOKBACK

      @series.ensure_sorted!
      recent = candles.last(LOOKBACK)
      trend = detect_trend(recent)
      strength = detect_strength(recent)
      displacement = displacement?(candles)
      vwap_behavior = classify_vwap_behavior(candles)

      Result.new(
        trend: trend,
        strength: strength,
        displacement: displacement,
        vwap_behavior: vwap_behavior
      )
    end

    private

    def default_result
      Result.new(trend: :range, strength: :weak, displacement: false, vwap_behavior: :around)
    end

    def detect_trend(recent)
      highs = recent.map(&:high)
      lows = recent.map(&:low)

      if increasing?(highs) && increasing?(lows)
        :bullish
      elsif decreasing?(highs) && decreasing?(lows)
        :bearish
      else
        :range
      end
    end

    def detect_strength(recent)
      bodies = recent.map { |c| (c.close.to_f - c.open.to_f).abs }
      avg_body = bodies.sum / bodies.size
      return :weak if avg_body.zero?

      large_moves = bodies.count { |b| b > avg_body * DISPLACE_BODY_MULT }
      return :strong if large_moves >= 3
      return :moderate if large_moves >= 1

      :weak
    end

    def displacement?(candles)
      last = candles.last
      bodies = candles.map { |c| (c.close.to_f - c.open.to_f).abs }
      avg_body = bodies.sum / bodies.size.to_f
      return false if avg_body.zero?

      avg_vol = candles.sum(&:volume) / candles.size.to_f
      body = (last.close.to_f - last.open.to_f).abs

      body > (avg_body * DISPLACE_BODY_MULT) &&
        last.volume.to_f > (avg_vol * DISPLACE_VOL_MULT) &&
        closes_near_extreme?(last)
    end

    def closes_near_extreme?(candle)
      range = candle.high.to_f - candle.low.to_f
      return false if range <= 0

      if candle.close.to_f > candle.open.to_f
        (candle.high.to_f - candle.close.to_f) / range < 0.2
      else
        (candle.close.to_f - candle.low.to_f) / range < 0.2
      end
    end

    def classify_vwap_behavior(candles)
      vw = @series.current_vwap
      return :around unless vw&.positive?

      last_close = candles.last.close.to_f
      chop = vwap_chop_crosses?(candles, vw)
      return :chop if chop

      pct = ((last_close - vw) / vw * 100.0).abs
      return :around if pct < 0.05

      last_close > vw ? :above : :below
    end

    def vwap_chop_crosses?(candles, vwap)
      return false if candles.size < CHOP_CROSS_MIN + 1

      crosses = 0
      candles.last(CHOP_CROSS_MIN + 1).each_cons(2) do |a, b|
        ca = a.close.to_f - vwap
        cb = b.close.to_f - vwap
        crosses += 1 if (ca * cb).negative?
      end
      crosses >= CHOP_CROSS_MIN
    end

    def increasing?(arr)
      arr.each_cons(2).all? { |a, b| b >= a }
    end

    def decreasing?(arr)
      arr.each_cons(2).all? { |a, b| b <= a }
    end
  end
end
