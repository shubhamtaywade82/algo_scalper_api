# frozen_string_literal: true

require "bigdecimal"

module Trading
  class DataFetcherService
    def fetch_historical_data(instrument:, interval: "5minute", lookback: 200, from: nil, to: nil)
      interval_key = interval.to_s.gsub("minute", "")

      # Use the instrument's built-in intraday_ohlc method
      instrument.intraday_ohlc(
        interval: interval_key,
        from_date: from&.strftime("%Y-%m-%d"),
        to_date: to&.strftime("%Y-%m-%d"),
        days: lookback
      )
    end

    def fetch_option_chain(instrument:, expiry: nil)
      # Use the instrument's built-in option chain method
      instrument.fetch_option_chain(expiry)
    end

    def fetch_derivative_quote(derivative)
      # Use the derivative's built-in subscription and LTP methods
      derivative.subscribe
      sleep 0.1
      derivative.ws_get
    end
  end
end
