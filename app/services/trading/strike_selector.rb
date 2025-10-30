# frozen_string_literal: true

require 'bigdecimal'

module Trading
  class StrikeSelector
    MIN_OPEN_INTEREST = 5_000

    def initialize(data_fetcher: DataFetcherService.new)
      @data_fetcher = data_fetcher
    end

    def select_for(instrument, signal: :long)
      spot = instrument.latest_ltp
      spot ||= fallback_spot(instrument)
      return unless spot

      expiry = next_expiry(instrument)
      scope = instrument.derivatives
      scope = scope.expiring_on(expiry) if expiry
      scope = signal == :long ? scope.calls : scope.puts

      scope.min_by { |derivative| (BigDecimal(derivative.strike_price.to_s) - spot).abs }
    end

    private

    def next_expiry(instrument)
      instrument.derivatives.upcoming.limit(1).pick(:expiry_date)
    end

    def fallback_spot(instrument)
      candles = @data_fetcher.fetch_historical_data(
        instrument: instrument,
        interval: '5minute',
        lookback: 5
      )
      last_close = candles.last&.dig(:close)
      last_close && BigDecimal(last_close.to_s)
    end
  end
end
