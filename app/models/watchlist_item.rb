# frozen_string_literal: true

class WatchlistItem < ApplicationRecord
  belongs_to :watchable, polymorphic: true, optional: true
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
end


