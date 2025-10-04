# frozen_string_literal: true

require "bigdecimal"

module Trading
  class DataFetcherService
    INTERVAL_IN_MINUTES = {
      "1minute" => 1,
      "3minute" => 3,
      "5minute" => 5,
      "10minute" => 10,
      "15minute" => 15
    }.freeze

    def initialize(client: Dhanhq.client)
      @client = client
    end

    def fetch_historical_data(security_id:, exchange_segment:, interval: "5minute", lookback: 200, from: nil, to: nil)
      interval_key = interval.to_s
      minutes = INTERVAL_IN_MINUTES.fetch(interval_key, 5)
      to_time = (to || Time.current).in_time_zone("Asia/Kolkata")
      from_time = (from || to_time - minutes.minutes * lookback)

      candles = @client.historical_intraday(
        security_id: security_id,
        exchange_segment: exchange_segment,
        interval: interval_key,
        from: from_time.iso8601,
        to: to_time.iso8601
      )

      normalize_candles(candles)
    end

    def fetch_option_chain(instrument:, expiry: nil)
      payload = {
        underlying_scrip: instrument.symbol_name,
        underlying_seg: instrument.exchange_segment
      }

      payload[:expiry] = expiry if expiry

      @client.option_chain(**payload)
    end

    def fetch_derivative_quote(derivative)
      Live::MarketFeedHub.instance.subscribe(segment: derivative.exchange_segment, security_id: derivative.security_id)
      sleep 0.1
      Live::TickCache.get(derivative.exchange_segment, derivative.security_id)
    end

    private

    def normalize_candles(candles)
      Array(candles).map do |entry|
        data = entry.respond_to?(:to_h) ? entry.to_h : entry
        {
          time: parse_time(data[:time_stamp] || data[:time] || data["timeStamp"] || data["time"]),
          open: big_decimal(data[:open]),
          high: big_decimal(data[:high]),
          low: big_decimal(data[:low]),
          close: big_decimal(data[:close]),
          volume: data[:volume] || data["volume"]
        }
      end.compact
    end

    def parse_time(value)
      return value if value.is_a?(Time)
      return Time.zone.parse(value.to_s) if value

      nil
    end

    def big_decimal(value)
      return if value.nil?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
