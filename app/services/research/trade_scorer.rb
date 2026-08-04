# frozen_string_literal: true

module Research
  # Simulates a single entry against a candidate's fetched bars and scores it:
  # entry price (per entry_model), exit at the last fetched bar, and MFE/MAE/
  # return relative to entry — answers "was the contract worth buying".
  # "How would we exit it" is answered separately per-strategy in
  # exit_simulations (Research::CandidateExitSimulator).
  class TradeScorer
    # Research-local liquidity/premium floor — deliberately not shared with
    # Options::IndexRules (live path), same isolation policy as StrikeResolver.
    # No bid/ask spread check: the rolling-option endpoint Research:: fetches
    # from doesn't return bid/ask, only OHLC/volume/oi/spot.
    MIN_VOLUME = 5_000
    MIN_PREMIUM = 5.0

    class << self
      def score!(candidate)
        bars = candidate.bars.to_a
        return mark_no_data!(candidate) if bars.empty?

        entry_index = entry_index_for(candidate, bars)
        return mark_no_data!(candidate) if entry_index.nil?

        entry_bar = bars[entry_index]
        entry_price = entry_price_for(candidate, entry_bar)
        return mark_no_data!(candidate) if entry_price.to_f <= 0
        return mark_illiquid!(candidate) unless liquid?(entry_bar, entry_price)

        # DhanHQ's expired-options "ATM"/"ATM+N" series re-resolves the strike per bar
        # as spot drifts (confirmed empirically — see PremiumLifecycleAnalyzer /
        # MarketDataFetcher). A real position holds one strike from entry onward, so
        # the forward window must only look at bars still quoting the entry bar's
        # actual_strike.
        window = same_strike_window(bars[entry_index..], entry_bar.actual_strike)
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
          exit_simulations: Research::CandidateExitSimulator.simulate(
            entry_price: entry_price, window: window, option_type: candidate.option_type
          ),
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

      def mark_illiquid!(candidate)
        candidate.update!(status: "illiquid")
        candidate
      end

      def liquid?(entry_bar, entry_price)
        entry_bar.volume.to_i >= MIN_VOLUME && entry_price.to_f >= MIN_PREMIUM
      end

      def same_strike_window(window, entry_strike)
        return window if entry_strike.blank?

        window.select { |bar| bar.actual_strike.to_i == entry_strike.to_i }
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
