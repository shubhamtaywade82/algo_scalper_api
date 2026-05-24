# frozen_string_literal: true

# Idempotent bulk load (db:seed). Uses upsert so reruns update names without duplicate rows.
# 2026 dates from NSE/BSE equity holiday circulars — verify when exchange publishes updates:
#   https://www.nseindia.com/resources/exchange-communication-holidays
#   https://www.bseindia.com/static/markets/marketinfo/listholi.aspx
#
# Muhurat / special sessions are not modeled as full-day closures here.

HOLIDAY_ROWS_2026 = [
  [Date.new(2026, 1, 26), 'Republic Day'],
  [Date.new(2026, 3, 3), 'Holi'],
  [Date.new(2026, 3, 26), 'Ram Navami'],
  [Date.new(2026, 3, 31), 'Mahavir Jayanti'],
  [Date.new(2026, 4, 3), 'Good Friday'],
  [Date.new(2026, 4, 14), 'Dr. Ambedkar Jayanti'],
  [Date.new(2026, 5, 1), 'Maharashtra Day'],
  [Date.new(2026, 5, 28), 'Bakri Id'],
  [Date.new(2026, 6, 26), 'Muharram'],
  [Date.new(2026, 9, 14), 'Ganesh Chaturthi'],
  [Date.new(2026, 10, 2), 'Mahatma Gandhi Jayanti'],
  [Date.new(2026, 10, 20), 'Dussehra'],
  [Date.new(2026, 11, 10), 'Diwali — Balipratipada'],
  [Date.new(2026, 11, 24), 'Gurunanak Jayanti'],
  [Date.new(2026, 12, 25), 'Christmas']
].freeze

EXCHANGES = %w[nse bse].freeze

now = Time.current
rows = HOLIDAY_ROWS_2026.flat_map do |observed_on, name|
  EXCHANGES.map do |exchange|
    {
      exchange: exchange,
      observed_on: observed_on,
      name: name,
      created_at: now,
      updated_at: now
    }
  end
end

# rubocop:disable Rails/SkipsModelValidations -- idempotent seed bulk upsert; rows built from static calendar
MarketHoliday.upsert_all(
  rows,
  unique_by: :index_market_holidays_on_exchange_and_observed_on_unique
)
# rubocop:enable Rails/SkipsModelValidations
MarketHoliday.refresh_market_calendar_cache

Rails.logger.info(
  "[db/seeds/market_holidays] Seeded market_holidays: #{MarketHoliday.count} rows " \
  "(NSE+BSE × #{HOLIDAY_ROWS_2026.size} dates for 2026)."
)
