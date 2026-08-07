# frozen_string_literal: true

class BacktestRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :strategy_version, class_name: 'Strategies::Version', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :symbol, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  def completed?
    status == 'completed'
  end
end
