# frozen_string_literal: true

# Audit trail for risk engine decisions.
# Records every time risk rules block, halt, or force-exit.
class RiskEvent < ApplicationRecord
  belongs_to :instrument, optional: true
  belongs_to :position_tracker, optional: true

  SEVERITIES = %w[info warning critical].freeze

  validates :event_type, presence: true
  validates :source, presence: true
  validates :severity, inclusion: { in: SEVERITIES }

  scope :critical, -> { where(severity: 'critical') }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..) }
  scope :recent, -> { order(created_at: :desc) }

  def critical? = severity == 'critical'
end
