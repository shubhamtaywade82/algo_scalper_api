# frozen_string_literal: true

module Research
  # Layer 4/5: a candidate strike/expiry tied to a Research::Signal, scored
  # with entry/exit simulation metrics (mfe/mae/return) once bars are fetched.
  class OptionCandidate < ApplicationRecord
    self.table_name = "research_option_candidates"

    STATUSES = %w[pending scored no_data failed].freeze

    belongs_to :research_signal, class_name: "Research::Signal"

    validates :underlying_symbol, :expiry_flag, :option_type, :strike_label, presence: true
    validates :status, inclusion: { in: STATUSES }

    # Scoped by interval (research_option_bars is additionally keyed by it)
    # and by a bounded window from the signal's own date, since strike_label
    # ("ATM") is a relative moneyness label reused across every session —
    # without the date bound, re-running the pipeline for the same
    # symbol/expiry_flag/strike_label on a *different* calendar day would
    # silently blend that unrelated day's bars into this candidate's window.
    def bars
      window_start = research_signal.signal_timestamp.beginning_of_day
      Research::OptionBar.where(
        underlying_symbol: underlying_symbol,
        expiry_flag: expiry_flag,
        option_type: option_type,
        strike_label: strike_label,
        interval: interval,
        ts: window_start..(window_start + 3.days)
      ).order(:ts)
    end
  end
end
