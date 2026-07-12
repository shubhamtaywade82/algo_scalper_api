# frozen_string_literal: true

module Research
  # Best-effort underlying market-context snapshot (ATR/ADX/RSI/MACD/VWAP
  # distance/swing structure) as of a given timestamp, built from the
  # existing persisted 1m `candles` table (Candles::Record) rather than a
  # live feed. Returns {} when there isn't enough history to compute
  # anything meaningful — callers must treat that as "unknown", not zero.
  class UnderlyingContextSnapshot
    MIN_CANDLES = 30
    LOOKBACK_MINUTES = 180

    class << self
      def at(symbol:, timestamp:, lookback_minutes: LOOKBACK_MINUTES)
        rows = Candles::Record
               .for_instrument(symbol.to_s.upcase)
               .for_timeframe("1m")
               .between(timestamp - lookback_minutes.minutes, timestamp)
               .order(:ts)
        return {} if rows.size < MIN_CANDLES

        series = build_series(symbol, rows)
        last = series.candles.last
        vwap = series.current_vwap

        {
          "close" => last&.close,
          "atr" => series.atr,
          "adx" => series.adx,
          "rsi" => series.rsi,
          "macd" => series.macd,
          "vwap" => vwap,
          "vwap_distance" => vwap_distance(last, vwap),
          "swing_high" => structure_flag(series) { |idx| series.swing_high?(idx, 3) },
          "swing_low" => structure_flag(series) { |idx| series.swing_low?(idx, 3) }
        }
      rescue StandardError => e
        Rails.logger.warn("[Research::UnderlyingContextSnapshot] failed for #{symbol} @ #{timestamp}: #{e.message}")
        {}
      end

      private

      def build_series(symbol, rows)
        series = CandleSeries.new(symbol: symbol, interval: "1")
        rows.each do |row|
          series.add_candle(
            Candle.new(timestamp: row.ts, open: row.open, high: row.high, low: row.low, close: row.close,
                       volume: row.volume)
          )
        end
        series
      end

      def vwap_distance(last, vwap)
        return nil unless last && vwap

        (last.close.to_f - vwap.to_f).round(4)
      end

      def structure_flag(series)
        idx = series.candles.size - 4
        return nil if idx < 3

        yield(idx)
      end
    end
  end
end
