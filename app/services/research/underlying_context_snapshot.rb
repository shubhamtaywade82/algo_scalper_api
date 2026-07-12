# frozen_string_literal: true

module Research
  # Best-effort underlying market-context snapshot (ATR/ADX/RSI/MACD/VWAP
  # distance/swing structure, plus Research::ContextClassifier's regime
  # labels) as of a given timestamp, built from the existing persisted 1m
  # `candles` table (Candles::Record) rather than a live feed. Returns {}
  # when there isn't enough history to compute anything meaningful —
  # callers must treat that as "unknown", not zero.
  class UnderlyingContextSnapshot
    MIN_CANDLES = 30
    LOOKBACK_MINUTES = 180
    SESSION_OPEN = { hour: 9, min: 15 }.freeze
    OPENING_RANGE_END = { hour: 9, min: 45 }.freeze

    class << self
      def at(symbol:, timestamp:, lookback_minutes: LOOKBACK_MINUTES)
        symbol = symbol.to_s.upcase
        rows = Candles::Record
               .for_instrument(symbol)
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
          "swing_low" => structure_flag(series) { |idx| series.swing_low?(idx, 3) },
          "regime" => Research::ContextClassifier.classify(
            series: series,
            opening_range_bars: opening_range_bars(symbol, timestamp),
            previous_session_close: previous_session_close(symbol, timestamp)
          )
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

      # Fetched independently of the main lookback window (which may not
      # reach back to session open for a late-session timestamp) so
      # opening-range-breakout classification works at any time of day.
      def opening_range_bars(symbol, timestamp)
        date = timestamp.to_date
        from = date.in_time_zone("Asia/Kolkata").change(hour: SESSION_OPEN[:hour], min: SESSION_OPEN[:min])
        to = date.in_time_zone("Asia/Kolkata").change(hour: OPENING_RANGE_END[:hour], min: OPENING_RANGE_END[:min])
        Candles::Record.for_instrument(symbol).for_timeframe("1m").between(from, to).order(:ts).to_a
      end

      def previous_session_close(symbol, timestamp)
        session_start = timestamp.to_date.in_time_zone("Asia/Kolkata").change(hour: SESSION_OPEN[:hour],
                                                                               min: SESSION_OPEN[:min])
        Candles::Record
          .for_instrument(symbol)
          .for_timeframe("1m")
          .where("ts < ?", session_start)
          .order(ts: :desc)
          .first
          &.close
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
