# frozen_string_literal: true

class BestIndicatorParam < ApplicationRecord
  belongs_to :instrument

  validates :interval, presence: true
  validates :params, presence: true
  validates :metrics, presence: true
  validates :score, presence: true

  # Fetch canonical best params for instrument + interval (combined optimization)
  scope :best_for, lambda { |instrument_id, interval|
    where(instrument_id: instrument_id, interval: interval, indicator: 'combined').limit(1)
  }

  # Fetch best params for a specific indicator
  scope :best_for_indicator, lambda { |instrument_id, interval, indicator|
    where(instrument_id: instrument_id, interval: interval, indicator: indicator.to_s).limit(1)
  }

  # Fetch all optimized indicators for instrument + interval
  scope :for_instrument_interval, lambda { |instrument_id, interval|
    where(instrument_id: instrument_id, interval: interval)
  }
end
