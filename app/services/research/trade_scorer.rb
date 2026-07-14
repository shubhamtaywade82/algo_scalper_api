# frozen_string_literal: true

module Research
  # Simulates a single entry against a candidate's fetched bars and scores it:
  # entry price (per entry_model), exit at the last fetched bar, and MFE/MAE/
  # return relative to entry. Intentionally simple (no target/SL/trailing) —
  # this answers "was the contract worth buying", not "how would we exit it".
  class TradeScorer
    class << self
      def score!(candidate)
        bars = candidate.bars.to_a
        return mark_no_data!(candidate) if bars.empty?

        entry_index = entry_index_for(candidate, bars)
        return mark_no_data!(candidate) if entry_index.nil?

        entry_bar = bars[entry_index]
        entry_price = entry_price_for(candidate, entry_bar)
        return mark_no_data!(candidate) if entry_price.to_f <= 0

        window = bars[entry_index..]
        exit_bar = window.last
        max_high = window.map { |bar| bar.high.to_f }.max
        min_low = window.map { |bar| bar.low.to_f }.min

        candidate.update!(
          entry_timestamp: entry_bar.ts,
          entry_price: entry_price,
          exit_timestamp: exit_bar.ts,
          exit_price: exit_bar.close,
          mfe_pct: Research::PercentChange.of(max_high, entry_price),
          mae_pct: Research::PercentChange.of(min_low, entry_price)&.abs,
          return_pct: Research::PercentChange.of(exit_bar.close, entry_price),
          holding_minutes: ((exit_bar.ts - entry_bar.ts) / 60).round,
          status: "scored"
        )
        candidate
      rescue StandardError => e
        Rails.logger.error("[Research::TradeScorer] candidate ##{candidate.id} failed: #{e.class}: #{e.message}")
        candidate.update!(status: "failed")
        candidate
      end

      private

      def mark_no_data!(candidate)
        candidate.update!(status: "no_data")
        candidate
      end

      # Returns nil (not 0) when no bar satisfies the entry model's condition —
      # callers must treat that as "no entry point found", not "enter at bar 0".
      def entry_index_for(candidate, bars)
        signal_ts = candidate.research_signal.signal_timestamp

        case candidate.entry_model
        when "same_candle_open", "signal_candle_close"
          bars.rindex { |bar| bar.ts <= signal_ts }
        else # "next_candle_open"
          bars.index { |bar| bar.ts > signal_ts }
        end
      end

      def entry_price_for(candidate, bar)
        candidate.entry_model == "signal_candle_close" ? bar.close : bar.open
      end
    end
  end
end
