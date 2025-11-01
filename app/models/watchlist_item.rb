# == Schema Information
#
# Table name: watchlist_items
#
#  id                        :integer         not null, primary key
#  segment                   :string          not null
#  security_id               :string          not null
#  kind                      :integer
#  label                     :string
#  active                    :boolean         not null
#  watchable_type            :string
#  watchable_id              :integer
#  created_at                :datetime        not null
#  updated_at                :datetime        not null
#
# Indexes
#
#  index_watchlist_items_on_segment_and_security_id  (segment,security_id) UNIQUE
#  index_watchlist_items_on_watchable               (watchable_type,watchable_id)
#
# Foreign Keys
#
#  fk_rails_...  (watchable_id => watchable_type)
#

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

  validate :kind_must_be_valid

  scope :active, -> { where(active: true) }
  scope :by_segment, ->(seg) { where(segment: seg) }
  scope :for, ->(seg, sid) { where(segment: seg, security_id: sid) }

  # Convenience accessors for the polymorphic association
  def instrument
    watchable if watchable_type == 'Instrument'
  end

  def derivative
    watchable if watchable_type == 'Derivative'
  end

  def kind=(value)
    @invalid_kind_value = nil
    super(value)
  rescue ArgumentError
    @invalid_kind_value = value
    super(nil)
  end

  private

  def kind_must_be_valid
    return unless defined?(@invalid_kind_value) && @invalid_kind_value

    errors.add(:kind, 'is not included in the list')
  end
end
