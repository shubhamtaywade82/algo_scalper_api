# frozen_string_literal: true

module Research
  # Classifies a CandleSeries snapshot into the categorical regime labels the
  # Research Kernel groups signals/lifecycles by (market structure, trend
  # strength, volatility regime, momentum, volume, time-of-day, VWAP
  # relation, liquidity sweep, opening-range breakout, gap). This turns the
  # raw indicator numbers Research::UnderlyingContextSnapshot already computes
  # into the buckets a Context -> Expectancy report groups by.
  #
  # Reuses the existing Smc::Detectors (pure, side-effect-free CandleSeries
  # computations already used by the live SMC scanner) for structure/BOS/CHoCH
  # and liquidity-sweep detection rather than re-deriving swing points here.
  #
  # Thresholds below are a documented first cut, not values calibrated
  # against historical data — expect to revisit them once the Context ->
  # Expectancy report has enough volume to show where the buckets should
  # actually sit.
  class ContextClassifier
    STRONG_ADX = 25
    WEAK_ADX = 18
    ATR_EXPANSION_RATIO = 1.15
    ATR_COMPRESSION_RATIO = 0.85
    ATR_LOOKBACK_BARS = 15
    RSI_OVERBOUGHT = 70
    RSI_BULLISH = 55
    RSI_BEARISH = 45
    RSI_OVERSOLD = 30
    VOLUME_SPIKE_RATIO = 1.5
    VOLUME_ABOVE_RATIO = 1.1
    VOLUME_BELOW_RATIO = 0.7
    VWAP_NEUTRAL_BAND_PCT = 0.05
    GAP_NEUTRAL_BAND_PCT = 0.15

    class << self
      # @param series [CandleSeries] underlying bars up to "now" (last candle = current)
      # @param opening_range_bars [Array<#open,#high,#low>] 09:15-09:45 IST bars for the
      #   same session as `series`'s last candle — used for ORB/gap only, fetched
      #   separately from `series` since the caller's lookback window may not reach back
      #   to session open.
      # @param previous_session_close [Numeric, nil] prior trading day's last close
      def classify(series:, opening_range_bars: [], previous_session_close: nil)
        return {} if series.candles.empty?

        structure = Smc::Detectors::Structure.new(series)
        liquidity = Smc::Detectors::Liquidity.new(series)

        {
          "market_structure" => structure.trend.to_s,
          "recent_bos" => structure.bos?,
          "recent_choch" => structure.choch?,
          "trend" => trend_bucket(series, structure),
          "volatility_regime" => volatility_regime(series),
          "momentum" => momentum_bucket(series),
          "volume_regime" => volume_regime(series),
          "time_context" => time_context(series),
          "vwap_relation" => vwap_relation(series),
          "liquidity_sweep" => liquidity_sweep(liquidity),
          "opening_range_breakout" => opening_range_breakout(series, opening_range_bars),
          "gap" => gap(opening_range_bars, previous_session_close)
        }
      end

      private

      def trend_bucket(series, structure)
        adx = series.adx(14)
        return "unknown" if adx.nil?

        structural_trend = structure.trend
        return "neutral" if structural_trend == :range

        bullish = structural_trend == :bullish
        if adx >= STRONG_ADX
          bullish ? "strong_bullish" : "strong_bearish"
        elsif adx >= WEAK_ADX
          bullish ? "weak_bullish" : "weak_bearish"
        else
          "neutral"
        end
      end

      def volatility_regime(series)
        current_atr = series.atr(14)
        return "unknown" if current_atr.nil? || current_atr.zero?
        return "unknown" if series.candles.size <= (14 + ATR_LOOKBACK_BARS)

        earlier_atr = earlier_series(series, ATR_LOOKBACK_BARS).atr(14)
        return "unknown" if earlier_atr.nil? || earlier_atr.zero?

        ratio = current_atr / earlier_atr
        return "expanding" if ratio >= ATR_EXPANSION_RATIO
        return "compressing" if ratio <= ATR_COMPRESSION_RATIO

        "stable"
      end

      def momentum_bucket(series)
        rsi = series.rsi(14)
        return "unknown" if rsi.nil?

        case rsi
        when RSI_OVERBOUGHT.. then "overbought"
        when RSI_BULLISH...RSI_OVERBOUGHT then "bullish_momentum"
        when RSI_BEARISH...RSI_BULLISH then "neutral_momentum"
        when RSI_OVERSOLD...RSI_BEARISH then "bearish_momentum"
        else "oversold"
        end
      end

      def volume_regime(series)
        bars = series.candles.last(20)
        return "unknown" if bars.size < 6

        recent = bars.last
        baseline = bars[0...-1]
        avg_volume = baseline.sum { |bar| bar.volume.to_f } / baseline.size
        return "unknown" if avg_volume.zero?

        ratio = recent.volume.to_f / avg_volume
        return "volume_spike" if ratio >= VOLUME_SPIKE_RATIO
        return "above_average" if ratio >= VOLUME_ABOVE_RATIO
        return "below_average" if ratio <= VOLUME_BELOW_RATIO

        "average"
      end

      def time_context(series)
        ts = series.candles.last.timestamp
        ts = ts.in_time_zone("Asia/Kolkata") if ts.respond_to?(:in_time_zone)
        minutes = (ts.hour * 60) + ts.min

        case minutes
        when 555...585 then "opening_range"   # 09:15-09:45
        when 585...690 then "morning"         # 09:45-11:30
        when 690...810 then "midday"          # 11:30-13:30
        when 810...900 then "afternoon"       # 13:30-15:00
        when 900...930 then "closing_hour"    # 15:00-15:30
        else "outside_session"
        end
      end

      def vwap_relation(series)
        vwap = series.current_vwap
        return "unknown" if vwap.nil? || vwap.zero?

        close = series.candles.last.close
        diff_pct = ((close - vwap) / vwap) * 100
        return "above_vwap" if diff_pct > VWAP_NEUTRAL_BAND_PCT
        return "below_vwap" if diff_pct < -VWAP_NEUTRAL_BAND_PCT

        "at_vwap"
      end

      def liquidity_sweep(liquidity)
        case liquidity.sweep_direction
        when :buy_side then "buy_side_sweep"
        when :sell_side then "sell_side_sweep"
        else "none"
        end
      end

      def opening_range_breakout(series, opening_range_bars)
        return "unknown" if opening_range_bars.blank?

        or_high = opening_range_bars.map { |bar| bar.high.to_f }.max
        or_low = opening_range_bars.map { |bar| bar.low.to_f }.min
        close = series.candles.last.close

        return "breakout_up" if close > or_high
        return "breakout_down" if close < or_low

        "inside_range"
      end

      def gap(opening_range_bars, previous_session_close)
        return "none" if previous_session_close.blank? || opening_range_bars.blank?

        prev_close = previous_session_close.to_f
        return "none" if prev_close.zero?

        today_open = opening_range_bars.first.open.to_f
        gap_pct = ((today_open - prev_close) / prev_close) * 100
        return "none" if gap_pct.abs < GAP_NEUTRAL_BAND_PCT

        gap_pct.positive? ? "gap_up" : "gap_down"
      end

      # A CandleSeries as it stood `drop_last_n` bars before its current last
      # candle — used to compare "ATR now" vs "ATR back then" without
      # depending on CandleSeries exposing a full historical ATR array.
      def earlier_series(series, drop_last_n)
        cutoff = series.candles.size - drop_last_n
        partial = CandleSeries.new(symbol: series.symbol, interval: series.interval)
        series.candles.first(cutoff).each { |candle| partial.add_candle(candle) }
        partial
      end
    end
  end
end
