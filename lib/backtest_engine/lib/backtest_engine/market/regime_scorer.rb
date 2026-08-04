# frozen_string_literal: true

module BacktestEngine
  module Market
    class RegimeScorer
      DEFAULT_EMA_PERIOD = 20
      NEUTRAL_SCORE = 50

      def initialize(series, ema_period: DEFAULT_EMA_PERIOD)
        @series = series
        @ema_period = ema_period
      end

      def score_at(index)
        return { score: NEUTRAL_SCORE, direction: :range } if index < @ema_period
        return { score: NEUTRAL_SCORE, direction: :range } if index >= @series.size

        direction = structure_direction(index)
        score = compute_score(index, direction)
        { score: score, direction: direction }
      end

      private

      def structure_direction(index)
        return :range if index < 2

        struct = @series.structure
        idx = index - 2
        struct[idx] || :range
      end

      def compute_score(index, direction)
        ema_val = @series.ema(@ema_period)[index]
        close = @series[index].close
        return NEUTRAL_SCORE unless ema_val && close

        pct_above_ema = ((close - ema_val) / ema_val) * 100.0
        raw = NEUTRAL_SCORE + (pct_above_ema.clamp(-10, 10) * 5)
        raw = raw.round.clamp(0, 100)

        if direction == :range
          raw = (raw + NEUTRAL_SCORE) / 2
        elsif direction == :bearish && raw > NEUTRAL_SCORE
          raw = (raw + NEUTRAL_SCORE) / 2
        elsif direction == :bullish && raw < NEUTRAL_SCORE
          raw = (raw + NEUTRAL_SCORE) / 2
        end

        raw.clamp(0, 100)
      end
    end
  end
end
