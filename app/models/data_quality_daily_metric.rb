# frozen_string_literal: true

class DataQualityDailyMetric < ApplicationRecord
  validates :trading_date, presence: true, uniqueness: true

  scope :recent_first, -> { order(trading_date: :desc) }
end
