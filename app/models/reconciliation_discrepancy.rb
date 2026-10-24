# frozen_string_literal: true

class ReconciliationDiscrepancy < ApplicationRecord
  belongs_to :reconciliation_run

  SEVERITIES = %w[info warning critical].freeze
  ENTITY_TYPES = %w[order position fund].freeze

  validates :entity_type, inclusion: { in: ENTITY_TYPES }
  validates :field_name, presence: true
  validates :severity, inclusion: { in: SEVERITIES }

  scope :critical, -> { where(severity: 'critical') }
  scope :unresolved, -> { where(resolution: [nil, 'pending']) }

  def critical? = severity == 'critical'
end
