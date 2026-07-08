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

    # Matches the interface EntryGuard.try_enter expects from TradingSignal,
    # so the same guard pipeline can score outcomes for either signal source.
    # `reason` here is the guard's block reason, not the strategy's original
    # signal reasoning — keep the latter intact in the `reason` column (the
    # signals dashboard parses ADX etc. out of it) and file the guard's
    # verdict under metadata instead.
    def record_entry_outcome(outcome, reason = nil, position_tracker: nil, extra_metadata: nil)
      mapped = outcome.to_s == "entered" ? "executed" : "blocked_by_guard"
      new_metadata = metadata.merge("entry_result_reason" => reason)
      new_metadata.merge!(extra_metadata) if extra_metadata.is_a?(Hash) && extra_metadata.any?
      update!(
        outcome: mapped,
        metadata: new_metadata,
        position_tracker: position_tracker || self.position_tracker
      )
    end
  end
end
