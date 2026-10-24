# frozen_string_literal: true

class AuditLog < ApplicationRecord
  EVENT_TYPES = %w[
    bot_start
    bot_stop
    mode_switch
    kill_switch_trip
    kill_switch_reset
    capital_reset
    square_off
    risk_breach
    reconciliation_mismatch
  ].freeze

  validates :event_type, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
