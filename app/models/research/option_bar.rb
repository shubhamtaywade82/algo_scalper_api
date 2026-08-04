# frozen_string_literal: true

module Research
  # Layer 2: normalized minute/5-min option-leg OHLC bar, keyed by contract
  # identity (symbol + expiry_flag + option_type + strike_label + interval + ts)
  # rather than by candidate, so bars fetched for one signal are reusable by
  # any other candidate that resolves to the same contract window.
  class OptionBar < ApplicationRecord
    self.table_name = "research_option_bars"

    belongs_to :research_raw_fetch, class_name: "Research::RawFetch", optional: true

    validates :underlying_symbol, :exchange_segment, :expiry_flag, :option_type,
              :strike_label, :interval, :ts, presence: true
  end
end
