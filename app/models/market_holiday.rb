# frozen_string_literal: true

# Exchange calendar closure (NSE / BSE) for a single calendar date (Asia/Kolkata).
# Source: official circulars — e.g. https://www.nseindia.com/resources/exchange-communication-holidays
class MarketHoliday < ApplicationRecord
  enum :exchange, { nse: 'nse', bse: 'bse' }, validate: true

  validates :exchange, presence: true
  validates :observed_on, presence: true
  validates :observed_on, uniqueness: { scope: :exchange }
  validates :name, length: { maximum: 200 }, allow_blank: true

  after_commit :refresh_market_calendar_cache, on: %i[create update destroy]

  # Distinct closure dates across all exchanges (union). Table stays small (yearly rows per exchange).
  def self.closure_date_strings
    distinct.order(:observed_on).pluck(:observed_on).map { |d| d.strftime('%Y-%m-%d') }
  end

  def self.refresh_market_calendar_cache
    Market::Calendar.clear_holiday_cache!
  end

  private

  def refresh_market_calendar_cache
    self.class.refresh_market_calendar_cache
  end
end
