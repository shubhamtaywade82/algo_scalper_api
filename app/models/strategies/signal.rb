# frozen_string_literal: true

module Strategies
  class Signal < ApplicationRecord
    self.table_name = "strategy_signals"

    ACTIONS = %w[buy_call buy_put exit hold].freeze
    OUTCOMES = %w[executed blocked_by_guard ignored_hold shadow].freeze

    belongs_to :strategy_record, class_name: "Strategies::Record", foreign_key: :strategy_id,
                                 inverse_of: :signals
    belongs_to :strategy_version, class_name: "Strategies::Version",
                                  inverse_of: :signals
    belongs_to :strategy_run, class_name: "Strategies::Run",
                              inverse_of: :signals
    belongs_to :position_tracker, optional: true

    validates :instrument_key, presence: true
    validates :action, presence: true, inclusion: { in: ACTIONS }
    validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
    validates :emitted_at, presence: true
  end
end
