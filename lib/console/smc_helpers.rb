# frozen_string_literal: true

# SMC Console Helpers
# Usage: Load this file in Rails console and use the helper methods
#
# Example:
#   load 'lib/console/smc_helpers.rb'
#   series_1h = fetch_candles_with_history(instrument, interval: "60", target_candles: 60)

module SmcConsoleHelpers
  extend self

  # Calculate trading days needed for a given interval and target candle count
  def trading_days_for_candles(interval_minutes, target_candles)
    # Indian market hours: 9:15 AM to 3:30 PM = 6.25 hours per day
    hours_per_day = 6.25
    candles_per_day = (hours_per_day * 60) / interval_minutes.to_i
    trading_days = (target_candles.to_f / candles_per_day).ceil
    # Add 50% buffer for holidays, partial days, etc.
    (trading_days * 1.5).ceil
  end

  # Fetch candles with sufficient historical data
  # Adds delay between requests to avoid rate limits
  def fetch_candles_with_history(instrument, interval:, target_candles:, delay_seconds: 1.0)
    interval_min = interval.to_i
    hours_per_day = 6.25
    candles_per_day = (hours_per_day * 60) / interval_min
    trading_days = ((target_candles.to_f / candles_per_day) * 1.5).ceil

    to_date = if defined?(Market::Calendar) && Market::Calendar.respond_to?(:today_or_last_trading_day)
                Market::Calendar.today_or_last_trading_day
              else
                Time.zone.today
              end

    from_date = if defined?(Market::Calendar) && Market::Calendar.respond_to?(:trading_days_ago)
                  Market::Calendar.trading_days_ago(trading_days)
                else
                  to_date - trading_days.days
                end

    # Add delay to avoid rate limits
    sleep(delay_seconds) if delay_seconds > 0

    raw_data = instrument.intraday_ohlc(
      interval: interval.to_s,
      from_date: from_date.to_s,
      to_date: to_date.to_s,
      days: trading_days
    )

    return nil if raw_data.blank?

    series = CandleSeries.new(symbol: instrument.symbol_name, interval: interval.to_s)
    series.load_from_raw(raw_data)
    series
  rescue StandardError => e
    Rails.logger.error("[SmcConsoleHelpers] Failed to fetch candles: #{e.class} - #{e.message}")
    nil
  end

  # Trim candle series to last N candles
  def trim_series(series, max_candles:)
    return series unless series&.respond_to?(:candles)

    trimmed = CandleSeries.new(symbol: series.symbol, interval: series.interval)
    series.candles.last(max_candles).each { |c| trimmed.add_candle(c) }
    trimmed
  end
end

# Make methods available in console
include SmcConsoleHelpers

puts "\n#{'=' * 80}"
puts '  SMC Console Helpers Loaded'
puts '=' * 80
puts "\nAvailable helper methods:"
puts '  - fetch_candles_with_history(instrument, interval:, target_candles:)'
puts '  - trading_days_for_candles(interval_minutes, target_candles)'
puts '  - trim_series(series, max_candles:)'
puts "\nExample usage:"
puts '  instrument = Instrument.find_by_sid_and_segment(security_id: "13", segment_code: "IDX_I")'
puts '  series_1h = fetch_candles_with_history(instrument, interval: "60", target_candles: 60)'
puts '  series_15m = fetch_candles_with_history(instrument, interval: "15", target_candles: 100)'
puts '  series_5m = fetch_candles_with_history(instrument, interval: "5", target_candles: 150)'
puts "\n"

