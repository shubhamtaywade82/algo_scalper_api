# frozen_string_literal: true

module Strategies
  class Record < ApplicationRecord
    self.table_name = "strategies"

    STATUSES = %w[draft deployed running stopped errored archived].freeze

    belongs_to :current_version, class_name: "Strategies::Version", optional: true
    has_many :versions, class_name: "Strategies::Version", foreign_key: :strategy_id,
                        dependent: :destroy, inverse_of: :strategy_record
    has_many :runs, class_name: "Strategies::Run", foreign_key: :strategy_id,
                    dependent: :destroy, inverse_of: :strategy_record
    has_many :signals, class_name: "Strategies::Signal", foreign_key: :strategy_id,
                       dependent: :destroy, inverse_of: :strategy_record

    validates :slug, presence: true, uniqueness: true
    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }
  end
end
