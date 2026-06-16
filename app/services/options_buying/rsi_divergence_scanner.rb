# frozen_string_literal: true

module OptionsBuying
  class RsiDivergenceScanner
    BEARISH = :bearish
    BULLISH = :bullish
    NEUTRAL = :neutral

    def self.scan!(index_key:)
      new(index_key: index_key).scan!
    end

    def initialize(index_key:)
      @index_key = index_key.to_s.upcase
    end

    WINDOW = 20

    def scan!
      return NEUTRAL unless Mode.rsi_bias_enabled?

      instrument = index_instrument
      return NEUTRAL unless instrument

      interval = (Mode.config.dig(:rsi_bias, :timeframe) || '15').to_s
      series = instrument.candle_series(interval: interval)
      return NEUTRAL unless series&.candles&.size.to_i >= WINDOW

      candles = series.candles.last(WINDOW)
      highs = candles.map(&:high)
      lows  = candles.map(&:low)
      rsi_values = rsi_window(series.candles)
      return NEUTRAL if rsi_values.compact.size < 10

      bias = detect_divergence(highs, lows, rsi_values)
      StateStore.set_rsi_bias(@index_key, bias) unless bias == NEUTRAL
      bias
    rescue StandardError => e
      Rails.logger.warn("[RsiDivergenceScanner] #{@index_key} #{e.class} - #{e.message}")
      NEUTRAL
    end

    private

    def index_instrument
      idx = IndexConfigLoader.load_indices.find { |c| c[:key].to_s == @index_key }
      return unless idx

      Instrument.find_by_sid_and_segment(
        security_id: idx[:sid],
        segment_code: idx[:segment]
      )
    end

    def detect_divergence(highs, lows, rsi_values)
      # Bearish: price prints a higher high while RSI prints a lower high.
      recent_high_idx = index_of_max(highs)
      prior_high_idx  = index_of_max(highs[0...-5])
      if recent_high_idx && prior_high_idx
        recent_rsi = rsi_values[recent_high_idx]
        prior_rsi  = rsi_values[prior_high_idx]
        if recent_rsi && prior_rsi &&
           highs[recent_high_idx] > highs[prior_high_idx] && recent_rsi < prior_rsi
          return BEARISH
        end
      end

      # Bullish: price prints a lower low while RSI prints a higher low.
      recent_low_idx = index_of_min(lows)
      prior_low_idx  = index_of_min(lows[0...-5])
      if recent_low_idx && prior_low_idx
        recent_rsi = rsi_values[recent_low_idx]
        prior_rsi  = rsi_values[prior_low_idx]
        if recent_rsi && prior_rsi &&
           lows[recent_low_idx] < lows[prior_low_idx] && recent_rsi > prior_rsi
          return BULLISH
        end
      end

      NEUTRAL
    end

    def index_of_max(values)
      values.each_with_index.max_by { |v, _| v }&.last
    end

    def index_of_min(values)
      values.each_with_index.min_by { |v, _| v }&.last
    end

    # Single-pass Wilder RSI over all closes, aligned to the trailing WINDOW
    # candles (leading nils for the warmup period). O(n) — no per-candle rebuild.
    def rsi_window(all_candles, period: 14)
      closes = all_candles.map(&:close)
      wilder_rsi_series(closes, period).last(WINDOW)
    end

    def wilder_rsi_series(closes, period)
      return Array.new(closes.size) if closes.size <= period

      gains = []
      losses = []
      closes.each_cons(2) do |prev, curr|
        change = curr.to_f - prev.to_f
        gains << (change.positive? ? change : 0.0)
        losses << (change.negative? ? -change : 0.0)
      end

      out = Array.new(closes.size) # index 0 has no prior close → nil
      avg_gain = gains.first(period).sum / period
      avg_loss = losses.first(period).sum / period
      out[period] = rsi_from(avg_gain, avg_loss)

      (period...gains.size).each do |i|
        avg_gain = ((avg_gain * (period - 1)) + gains[i]) / period
        avg_loss = ((avg_loss * (period - 1)) + losses[i]) / period
        out[i + 1] = rsi_from(avg_gain, avg_loss)
      end
      out
    end

    def rsi_from(avg_gain, avg_loss)
      return 50.0 if avg_loss.zero?

      rs = avg_gain / avg_loss
      100.0 - (100.0 / (1.0 + rs))
    end
  end
end
