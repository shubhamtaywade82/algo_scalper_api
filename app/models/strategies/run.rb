# frozen_string_literal: true

module Strategies
  class Run < ApplicationRecord
    self.table_name = "strategy_runs"

    STOP_REASONS = %w[manual crash kill_switch market_close error_limit].freeze

    belongs_to :strategy, class_name: "Strategies::Record"
    belongs_to :strategy_version, class_name: "Strategies::Version"
    has_many :signals, class_name: "Strategies::Signal", dependent: :destroy

    validates :stop_reason, inclusion: { in: STOP_REASONS }, allow_nil: true
  end
end
