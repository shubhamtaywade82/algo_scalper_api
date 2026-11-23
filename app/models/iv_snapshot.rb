# frozen_string_literal: true

class IvSnapshot < ApplicationRecord
  validates :index_key, presence: true
  validates :snapshot_date, presence: true
  validates :strike_price, presence: true
  validates :option_type, presence: true, inclusion: { in: %w[CE PE] }

  scope :for_index, ->(index_key) { where(index_key: index_key.to_s) }
  scope :latest, -> { order(snapshot_date: :desc) }

  def self.historical_iv(index_key:, days: 30)
    for_index(index_key)
      .where(snapshot_date: days.days.ago.to_date..)
      .latest
      .limit(days)
      .pluck(:implied_volatility)
      .compact
  end

  def self.latest_for(index_key:)
    for_index(index_key).latest.first
  end
end
