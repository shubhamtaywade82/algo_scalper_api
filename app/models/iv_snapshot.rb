# == Schema Information
#
# Table name: iv_snapshots
#
#  id                 :integer          not null, primary key
#  index_key          :string           not null
#  snapshot_date      :date             not null
#  implied_volatility :decimal(8, 4)
#  strike_price       :decimal(15, 5)
#  option_type        :string(2)
#  underlying_ltp     :decimal(15, 5)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_iv_snapshots_on_index_key_and_snapshot_date  (index_key,snapshot_date)
#  index_iv_snapshots_unique                          (index_key,snapshot_date,strike_price,option_type) UNIQUE
#

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
      .latest
      .limit(days)
      .pluck(:implied_volatility)
      .compact
  end
end
