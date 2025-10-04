# frozen_string_literal: true

class WatchlistItem < ApplicationRecord
  belongs_to :watchable, polymorphic: true, optional: true
  # belongs_to :instrument, polymorphic: true, optional: true
  # belongs_to :derivative, polymorphic: true, optional: true

  # TODO: Remove this once we have a proper mapping of segments to exchanges
  ALLOWED_SEGMENTS = %w[
    IDX_I NSE_EQ NSE_FNO NSE_CURRENCY BSE_EQ MCX_COMM BSE_CURRENCY BSE_FNO
  ].freeze

  validates :segment, presence: true, inclusion: { in: ALLOWED_SEGMENTS }
  validates :security_id, presence: true
  validates :security_id, uniqueness: { scope: :segment }

  # Avoid enum name 'index' to prevent ambiguous method names
  enum :kind, {
    index_value: 0,
    equity: 1,
    derivative: 2,
    currency: 3,
    commodity: 4
  }

  scope :active, -> { where(active: true) }
  scope :by_segment, ->(seg) { where(segment: seg) }
  scope :for, ->(seg, sid) { where(segment: seg, security_id: sid) }

  # Convenience accessors for the polymorphic association
  def instrument
    watchable if watchable_type == "Instrument"
  end

  def derivative
    watchable if watchable_type == "Derivative"
  end
end


