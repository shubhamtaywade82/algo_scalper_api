# frozen_string_literal: true

module Research
  # End-to-end orchestrator: signal -> candidate strikes -> option bar fetch
  # -> scoring. Returns candidates ranked best-to-worst by return_pct so
  # callers can immediately compare ATM vs ATM+/-N and near vs next expiry.
  class Pipeline
    class << self
      def run(signal:, expiry_flags: ["WEEK"], max_distance: 2, entry_model: "next_candle_open", days_forward: 1)
        candidates = Research::CandidateBuilder.build(
          signal: signal, expiry_flags: expiry_flags, max_distance: max_distance, entry_model: entry_model
        )
        return [] if candidates.empty?

        from_date, to_date = fetch_window(signal, days_forward)

        candidates.each do |candidate|
          Research::OptionCandleFetcher.call(
            symbol: signal.underlying_symbol,
            option_type: candidate.option_type,
            expiry_flag: candidate.expiry_flag,
            strike_label: candidate.strike_label,
            dhan_strike_param: candidate.metadata["dhan_strike_param"],
            from_date: from_date,
            to_date: to_date
          )
          Research::TradeScorer.score!(candidate)
        end

        candidates.map(&:reload).sort_by { |candidate| -(candidate.return_pct || -Float::INFINITY) }
      end

      private

      def fetch_window(signal, days_forward)
        base = signal.signal_timestamp.to_date
        [base.strftime("%Y-%m-%d"), (base + days_forward).strftime("%Y-%m-%d")]
      end
    end
  end
end
