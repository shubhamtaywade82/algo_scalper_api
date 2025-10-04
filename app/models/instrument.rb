# frozen_string_literal: true

require "bigdecimal"

class Instrument < ApplicationRecord
  include InstrumentHelpers

  has_many :derivatives, dependent: :destroy
  has_many :position_trackers, dependent: :restrict_with_error

  scope :enabled, -> { where(enabled: true) }

  validates :security_id, presence: true, uniqueness: true
  validates :symbol_name, presence: true
  validates :exchange_segment, presence: true, unless: -> { exchange.present? && segment.present? }

  def subscribe!
    subscribe
  end

  def unsubscribe!
    unsubscribe
  end

  def latest_ltp
    price = ws_ltp || quote_ltp || fetch_ltp_from_api
    price.present? ? BigDecimal(price.to_s) : nil
  end

  def option_chain(expiry: nil)
    Trading::DataFetcherService.new.fetch_option_chain(
      instrument: self,
      expiry: expiry
    )
  end
end
