# frozen_string_literal: true

require "date"

class DhanHqApiBars
  DEFAULT_CLIENT_PATH = File.expand_path("../../dhanhq-client", __dir__)
  SUPPORTED_INTERVALS = %w[1 5 15 25 60].freeze

  def initialize(client_path: ENV["DHANHQ_CLIENT_PATH"] || DEFAULT_CLIENT_PATH)
    require File.join(client_path, "lib", "dhan_hq")
    DhanHQ.configure_with_env
  end

  def fetch(exchange_segment:, symbol:, interval:, days:)
    validate_inputs!(exchange_segment: exchange_segment, symbol: symbol, interval: interval, days: days)

    instrument = DhanHQ::Models::Instrument.find(exchange_segment, symbol, exact_match: true)
    raise ArgumentError, "Instrument not found for #{exchange_segment}:#{symbol}" if instrument.nil?

    to_date = nearest_trading_day(Date.today)
    from_date = nearest_trading_day(to_date - days)
    bars = instrument.intraday(
      from_date: from_date.strftime("%Y-%m-%d"),
      to_date: to_date.strftime("%Y-%m-%d"),
      interval: interval.to_s
    )

    { instrument: instrument, bars: bars, from_date: from_date, to_date: to_date }
  end

  private

  def validate_inputs!(exchange_segment:, symbol:, interval:, days:)
    raise ArgumentError, "exchange_segment is required" if exchange_segment.to_s.strip.empty?
    raise ArgumentError, "symbol is required" if symbol.to_s.strip.empty?
    raise ArgumentError, "days must be greater than 0" unless days.is_a?(Integer) && days.positive?
    raise ArgumentError, "Unsupported interval #{interval}" unless SUPPORTED_INTERVALS.include?(interval.to_s)
  end

  def nearest_trading_day(date)
    return date unless weekend?(date)

    date - weekend_offset(date)
  end

  def weekend?(date)
    date.saturday? || date.sunday?
  end

  def weekend_offset(date)
    date.saturday? ? 1 : 2
  end
end
