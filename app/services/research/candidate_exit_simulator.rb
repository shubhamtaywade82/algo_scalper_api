# frozen_string_literal: true

module Research
  # Adapts a strike-locked window of Research::OptionBar records into the
  # hash-array shape Research::ExitCaptureAnalyzer expects, and runs every
  # registered exit strategy against it. underlying_candles is synthesized
  # from each bar's own `spot` field (open=high=low=close=spot) — sufficient
  # for the EMA-based strategies, which only read :close; option bars don't
  # carry real underlying OHLC.
  class CandidateExitSimulator
    class << self
      def simulate(entry_price:, window:, option_type:)
        return {} if window.blank? || entry_price.to_f <= 0

        option_candles = window.map { |bar| to_candle(bar) }
        underlying_candles = window.map { |bar| to_synthetic_underlying_candle(bar) }
        peak_bar = window.max_by { |bar| bar.high.to_f }
        # A long CE wants the underlying rising (breakout up); a long PE wants it
        # falling — same "in my favor" direction the EMA9/divergence strategies check.
        breakout_type = option_type.to_s.upcase == "PE" ? :bearish : :bullish

        trade_opp = { breakout_type: breakout_type, entry_time: window.first.ts, entry_index: 0 }
        expansion_context = {
          entry_price: entry_price.to_f,
          peak_price: peak_bar.high.to_f,
          peak_time: peak_bar.ts
        }

        Research::ExitCaptureAnalyzer.run(underlying_candles, option_candles, trade_opp, expansion_context)
      rescue StandardError => e
        Rails.logger.error("[Research::CandidateExitSimulator] failed: #{e.class}: #{e.message}")
        {}
      end

      private

      def to_candle(bar)
        {
          timestamp: bar.ts, open: bar.open.to_f, high: bar.high.to_f, low: bar.low.to_f,
          close: bar.close.to_f, volume: bar.volume.to_i, oi: bar.oi.to_i, iv: bar.iv.to_f
        }
      end

      def to_synthetic_underlying_candle(bar)
        spot = bar.spot.to_f
        { timestamp: bar.ts, open: spot, high: spot, low: spot, close: spot, volume: 0 }
      end
    end
  end
end
