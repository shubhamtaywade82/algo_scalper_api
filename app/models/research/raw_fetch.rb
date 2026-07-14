# frozen_string_literal: true

module Research
  # Layer 1: immutable audit copy of a raw DhanHQ API response, kept for
  # replay/reprocessing after normalizer changes.
  class RawFetch < ApplicationRecord
    self.table_name = "research_raw_fetches"

    has_many :option_bars, class_name: "Research::OptionBar", dependent: :nullify

    validates :endpoint, :fetched_at, presence: true
  end
end
