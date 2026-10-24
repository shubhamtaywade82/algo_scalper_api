# frozen_string_literal: true

class ReconciliationRun < ApplicationRecord
  has_many :discrepancies, class_name: 'ReconciliationDiscrepancy', dependent: :destroy

  STATUSES = %w[running passed failed error].freeze
  MODES = %w[paper live].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }

  scope :recent, -> { order(created_at: :desc) }
  scope :failed, -> { where(status: 'failed') }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..) }

  def passed? = status == 'passed'
  def failed? = status == 'failed'

  def complete!(new_status)
    update!(status: new_status, completed_at: Time.current)
  end

  def duration_seconds
    return nil unless completed_at && started_at

    (completed_at - started_at).round(2)
  end
end
