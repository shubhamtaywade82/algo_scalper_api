# frozen_string_literal: true

module Research
  # Layer 3: a signal-time snapshot (spot, direction, strategy context) that
  # anchors option-candidate research. Distinct from the live TradingSignal /
  # Strategies::Signal models — this table never feeds order placement.
  class Signal < ApplicationRecord
    self.table_name = "research_signals"

    DIRECTIONS = %w[bullish bearish no_trade].freeze

    has_many :option_candidates, class_name: "Research::OptionCandidate", dependent: :destroy

    validates :underlying_symbol, :signal_timestamp, :spot_price, presence: true
    validates :direction, inclusion: { in: DIRECTIONS }
  end
end
