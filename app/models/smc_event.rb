# frozen_string_literal: true

class SmcEvent < ApplicationRecord
  validates :stream, :event_type, :correlation_id, :payload, presence: true

  before_validation :ensure_sequence

  private

  def ensure_sequence
    return if sequence.present?

    self.sequence = (SmcEvent.where(correlation_id: correlation_id).maximum(:sequence) || 0) + 1
  end
end
