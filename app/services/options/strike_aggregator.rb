# frozen_string_literal: true

module Options
  # Combines HistoricalCalibrationEngine results for ATM, OTM1, OTM2 strikes
  # into a single weighted stats hash for use by CalibrationConfigPatchBuilder.
  #
  # Input: each *_stats is a Hash from HistoricalCalibrationEngine#call, containing
  # :ce and :pe leg summaries (avg_gain, avg_retrace_abs, avg_loss_abs, etc.)
  #
  # Output: a combined stats Hash with the same keys as engine[:combined],
  # weighted across the three strikes. Nil inputs are skipped; weights are
  # redistributed proportionally.
  class StrikeAggregator
    WEIGHTS = { atm: 0.50, otm1: 0.25, otm2: 0.25 }.freeze

    def self.combine(atm_stats:, otm1_stats:, otm2_stats:)
      new(atm: atm_stats, otm1: otm1_stats, otm2: otm2_stats).combine
    end

    def initialize(atm:, otm1:, otm2:)
      @entries = { atm: atm, otm1: otm1, otm2: otm2 }
    end

    def combine
      available = @entries.compact
      return fallback_empty if available.empty?

      # Redistribute weights to available entries
      # normalized: [[:atm, 0.5], [:otm1, 0.25], ...]  — flat pairs, not a Hash
      total_weight = available.keys.sum { |k| WEIGHTS[k] }
      normalized   = available.map { |k, _| [k, WEIGHTS[k] / total_weight] }

      {
        avg_gain: weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_gain) },
        avg_retrace_abs: weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_retrace_abs) },
        avg_loss_abs: weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_loss_abs) },
        avg_oc: weighted_avg(normalized) { |stats| avg_ce_pe(stats, :avg_oc) },
        oc_stddev: weighted_avg(normalized) { |stats| avg_ce_pe(stats, :oc_stddev) },
        sessions: {
          morning_oc: weighted_avg(normalized) { |stats| avg_session(stats, :morning_oc) },
          midday_oc: weighted_avg(normalized) { |stats| avg_session(stats, :midday_oc) },
          afternoon_oc: weighted_avg(normalized) { |stats| avg_session(stats, :afternoon_oc) }
        }
      }
    end

    private

    # Available entries: [[:key, normalized_weight], ...]
    def weighted_avg(entries, &)
      entries.sum { |(key, weight)| weight * yield(@entries[key]).to_f }.round(4)
    end

    def avg_ce_pe(stats, key)
      ce = stats.dig(:ce, key).to_f
      pe = stats.dig(:pe, key).to_f
      (ce + pe) / 2.0
    end

    def avg_session(stats, session_key)
      ce = stats.dig(:ce, :sessions, session_key).to_f
      pe = stats.dig(:pe, :sessions, session_key).to_f
      (ce + pe) / 2.0
    end

    def fallback_empty
      { avg_gain: 0.0, avg_retrace_abs: 0.0, avg_loss_abs: 0.0, avg_oc: 0.0, oc_stddev: 0.0,
        sessions: { morning_oc: 0.0, midday_oc: 0.0, afternoon_oc: 0.0 } }
    end
  end
end
