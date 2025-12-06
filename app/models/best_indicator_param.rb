# frozen_string_literal: true

class BestIndicatorParam < ApplicationRecord
  belongs_to :instrument

  validates :interval, presence: true
  validates :params, presence: true
  validates :metrics, presence: true
  validates :score, presence: true

  # Fetch canonical best params for instrument + interval (combined optimization)
  scope :best_for, ->(instrument_id, interval) do
    where(instrument_id: instrument_id, interval: interval, indicator: 'combined').limit(1)
  end

  # Fetch best params for a specific indicator
  scope :best_for_indicator, ->(instrument_id, interval, indicator) do
    where(instrument_id: instrument_id, interval: interval, indicator: indicator.to_s).limit(1)
  end

  # Fetch all optimized indicators for instrument + interval
  scope :for_instrument_interval, ->(instrument_id, interval) do
    where(instrument_id: instrument_id, interval: interval)
  end
end

