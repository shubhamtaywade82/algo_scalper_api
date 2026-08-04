# frozen_string_literal: true

module Research
  # End-to-end "premium lifecycle" orchestrator: fetches the full option
  # board (ATM+/-max_distance, CE and PE) for a symbol/expiry/date window,
  # traces each contract's premium lifecycle from a single anchor timestamp
  # (a detected event, a Research::Signal, or plain session open), attaches
  # a best-effort underlying-market snapshot at entry and at peak, and
  # persists the result so strikes/expiries/sessions can be compared later.
  class LifecycleRunner
    class << self
      def run(symbol:, spot:, expiry_flag:, entry_ts:, from_date:, to_date:, max_distance: 10, interval: "5",
              thresholds: Research::PremiumLifecycleAnalyzer::DEFAULT_THRESHOLDS)
        board = Research::BoardFetcher.call(
          symbol: symbol, spot: spot, expiry_flag: expiry_flag, from_date: from_date, to_date: to_date,
          max_distance: max_distance, interval: interval
        )

        # Shared across every contract in the board: they all resolve to the
        # same anchor entry_ts, so the "entry" underlying-context snapshot
        # would otherwise be recomputed identically up to (2 * max_distance+1)
        # times. Keyed by the analyzer's snapped entry bar timestamp so a
        # contract whose bars don't line up with the others still gets its
        # own correct snapshot instead of a stale cached one.
        entry_context_cache = {}

        lifecycles = board.flat_map do |option_type, strikes|
          strikes.map do |strike_label, bars|
            persist_lifecycle(symbol, expiry_flag, option_type, strike_label, interval, entry_ts, bars, thresholds,
                              entry_context_cache)
          end
        end

        lifecycles.compact.sort_by { |lifecycle| -(lifecycle.peak_return_pct || -Float::INFINITY) }
      end

      private

      def persist_lifecycle(symbol, expiry_flag, option_type, strike_label, interval, entry_ts, bars, thresholds,
                            entry_context_cache)
        # entry_ts (the anchor) is the record's identity — find_or_initialize_by
        # keys on it and it must never be overwritten by the analyzer's result,
        # which reports the snapped first-bar-at-or-after timestamp instead
        # (they can legitimately differ when the anchor doesn't land exactly on
        # a bar boundary). Overwriting it broke idempotent re-runs: a second
        # run with the same anchor would fail to find this row, build a
        # duplicate, and crash on the unique index.
        record = Research::PremiumLifecycle.find_or_initialize_by(
          underlying_symbol: symbol.to_s.upcase, expiry_flag: expiry_flag, option_type: option_type,
          strike_label: strike_label, interval: interval.to_s, entry_ts: entry_ts
        )
        record.actual_strike = bars.first&.actual_strike

        begin
          result = Research::PremiumLifecycleAnalyzer.analyze(
            bars.map { |bar| { ts: bar.ts, open: bar.open.to_f, high: bar.high.to_f, low: bar.low.to_f, close: bar.close.to_f } },
            entry_ts: entry_ts, thresholds: thresholds
          )

          if result[:status] == "no_data"
            record.status = "no_data"
          else
            record.assign_attributes(result.except(:status, :entry_ts))
            record.underlying_context = underlying_context_for(symbol, result, entry_context_cache)
            record.status = "computed"
          end
        rescue StandardError => e
          Rails.logger.error(
            "[Research::LifecycleRunner] #{symbol} #{option_type} #{strike_label} failed: #{e.class}: #{e.message}"
          )
          record.status = "failed"
        end

        record.save!
        record
      rescue StandardError => e
        Rails.logger.error(
          "[Research::LifecycleRunner] persist failed for #{symbol} #{option_type} #{strike_label}: #{e.class}: #{e.message}"
        )
        nil
      end

      def underlying_context_for(symbol, result, entry_context_cache)
        entry_context_cache[result[:entry_ts]] ||=
          Research::UnderlyingContextSnapshot.at(symbol: symbol, timestamp: result[:entry_ts])

        {
          "entry" => entry_context_cache[result[:entry_ts]],
          "peak" => Research::UnderlyingContextSnapshot.at(symbol: symbol, timestamp: result[:peak_ts])
        }
      end
    end
  end
end
