# frozen_string_literal: true

module Research
  # A single contract's premium path from an anchor timestamp (session open,
  # detected event, or a Research::Signal's signal_timestamp) through its
  # peak and decay. Standalone from Research::Signal/OptionCandidate — a
  # lifecycle answers "how did this contract's premium evolve", independent
  # of whether/how it would have been traded.
  class PremiumLifecycle < ApplicationRecord
    self.table_name = "research_premium_lifecycles"

    STATUSES = %w[pending computed no_data failed].freeze

    validates :underlying_symbol, :expiry_flag, :option_type, :strike_label, :entry_ts, presence: true
    validates :status, inclusion: { in: STATUSES }
  end
end
