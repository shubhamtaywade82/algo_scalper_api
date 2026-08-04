# frozen_string_literal: true

module Trading
  class TrendScorer
    attr_reader :series_5m, :series_15m

    def initialize(series_5m:, series_15m: nil)
      @series_5m = series_5m
      @series_15m = series_15m
    end

    def call
      return { score: 0, bias: :neutral, details: {} } if series_5m.candles.size < 20

      components = {
        market_structure: score_market_structure, # 40 pts
        vwap_bias: score_vwap_bias,               # 20 pts
        supertrend: score_supertrend,             # 15 pts
        mtf_alignment: score_mtf_alignment        # 25 pts
      }

      raw_score = components.values.sum { |v| v[:score] }

      # Directional bias
      bias = determine_bias(components)

      # ADX Filter: If trend is weak, slash total score by 50%
      adx_value = series_5m.adx(14) || 0
      final_score = adx_value < 20 ? (raw_score * 0.5) : raw_score

      {
        score: final_score.round(2),
        bias: bias,
        adx: adx_value.round(2),
        components: components
      }
    end

    private

    def score_market_structure
      # Uptrend: HH + HL
      # Downtrend: LH + LL
      # We check recent 3 swings
      highs = series_5m.candles.last(30).select.with_index { |_, i| series_5m.swing_high?(series_5m.candles.size - 30 + i) }.map(&:high)
      lows = series_5m.candles.last(30).select.with_index { |_, i| series_5m.swing_low?(series_5m.candles.size - 30 + i) }.map(&:low)

      return { score: 0, bias: :neutral } if highs.size < 2 || lows.size < 2

      is_uptrend = highs.last > highs[-2] && lows.last > lows[-2]
      is_downtrend = highs.last < highs[-2] && lows.last < lows[-2]

      return { score: 40, bias: :bullish } if is_uptrend
      return { score: 40, bias: :bearish } if is_downtrend

      { score: 0, bias: :neutral }
    end

    def score_vwap_bias
      ltp = series_5m.candles.last.close
      vwap = series_5m.current_vwap
      return { score: 0, bias: :neutral } unless vwap

      return { score: 20, bias: :bullish } if ltp > vwap
      return { score: 20, bias: :bearish } if ltp < vwap

      { score: 0, bias: :neutral }
    end

    def score_supertrend
      signal = series_5m.supertrend_signal
      case signal
      when :long_entry, :bullish
        { score: 15, bias: :bullish }
      when :short_entry, :bearish
        { score: 15, bias: :bearish }
      else
        { score: 0, bias: :neutral }
      end
    end

    def score_mtf_alignment
      return { score: 0, bias: :neutral } unless series_15m && series_15m.candles.size >= 10

      # Simplified 15m bias: price vs 20 EMA
      ema_15m = series_15m.ema(20)
      last_15m_close = series_15m.candles.last.close

      return { score: 0, bias: :neutral } unless ema_15m

      return { score: 25, bias: :bullish } if last_15m_close > ema_15m
      return { score: 25, bias: :bearish } if last_15m_close < ema_15m

      { score: 0, bias: :neutral }
    end

    def determine_bias(components)
      bullish_count = components.values.count { |v| v[:bias] == :bullish }
      bearish_count = components.values.count { |v| v[:bias] == :bearish }

      return :bullish if bullish_count > bearish_count && bullish_count >= 2
      return :bearish if bearish_count > bullish_count && bearish_count >= 2

      :neutral
    end
  end
end
