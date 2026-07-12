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

    def bars
      Research::OptionBar.where(
        underlying_symbol: underlying_symbol,
        expiry_flag: expiry_flag,
        option_type: option_type,
        strike_label: strike_label
      ).order(:ts)
    end
  end
end
