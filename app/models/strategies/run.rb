# frozen_string_literal: true

module Strategies
  class Run < ApplicationRecord
    self.table_name = "strategy_runs"

    STOP_REASONS = %w[manual crash kill_switch market_close error_limit].freeze

    belongs_to :strategy_record, class_name: "Strategies::Record", foreign_key: :strategy_id,
                                 inverse_of: :runs
    belongs_to :strategy_version, class_name: "Strategies::Version",
                                  inverse_of: :runs
    has_many :signals, class_name: "Strategies::Signal", foreign_key: :strategy_run_id,
                       dependent: :destroy, inverse_of: :strategy_run

    validates :stop_reason, inclusion: { in: STOP_REASONS }, allow_nil: true
  end
end
