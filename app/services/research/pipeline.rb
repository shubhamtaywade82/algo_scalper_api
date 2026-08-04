# frozen_string_literal: true

module Research
  # End-to-end orchestrator: signal -> candidate strikes -> option bar fetch
  # -> scoring. Returns candidates ranked best-to-worst by return_pct so
  # callers can immediately compare ATM vs ATM+/-N and near vs next expiry.
  class Pipeline
    class << self
      def run(signal:, expiry_flags: ["WEEK"], max_distance: 2, entry_model: "next_candle_open", days_forward: 1,
              interval: "5")
        candidates = Research::CandidateBuilder.build(
          signal: signal, expiry_flags: expiry_flags, max_distance: max_distance, entry_model: entry_model,
          interval: interval
        )
        return [] if candidates.empty?

        from_date, to_date = fetch_window(signal, days_forward)

        candidates.each do |candidate|
          score_candidate(candidate, from_date, to_date, interval)
        end

        candidates.sort_by { |candidate| -(candidate.return_pct || -Float::INFINITY) }
      end

      private

      # A fetch/scoring failure for one candidate must not lose the results
      # already computed for the others — mirrors LifecycleRunner's per-contract
      # isolation. TradeScorer.score! already self-heals into status: "failed"
      # for its own exceptions; this only needs to guard the fetch call.
      def score_candidate(candidate, from_date, to_date, interval)
        Research::OptionCandleFetcher.call(
          symbol: candidate.underlying_symbol,
          option_type: candidate.option_type,
          expiry_flag: candidate.expiry_flag,
          strike_label: candidate.strike_label,
          dhan_strike_param: candidate.metadata["dhan_strike_param"],
          from_date: from_date,
          to_date: to_date,
          interval: interval
        )
        Research::TradeScorer.score!(candidate)
      rescue StandardError => e
        Rails.logger.error("[Research::Pipeline] candidate ##{candidate.id} failed: #{e.class}: #{e.message}")
        candidate.update!(status: "failed")
      end

      def fetch_window(signal, days_forward)
        base = signal.signal_timestamp.to_date
        [base.strftime("%Y-%m-%d"), (base + days_forward).strftime("%Y-%m-%d")]
      end
    end
  end
end
