# frozen_string_literal: true

module Trading
  class StrikeSelector
    MIN_OPEN_INTEREST = 5_000

    def initialize(fetcher: Trading::DataFetcherService.new)
      @fetcher = fetcher
    end

    def select_for(index_instrument, signal: :long)
      expiry = find_next_expiry(index_instrument)
      chain = @fetcher.fetch_option_chain(instrument: index_instrument, expiry: expiry)
      return nil unless chain

      # Expect chain to have arrays/hashes; normalize to contracts with fields we need
      contracts = normalize_chain(chain)
      type = (signal == :long ? 'CALL' : 'PUT')

      filtered = contracts.select do |c|
        c[:option_type] == type && c[:open_interest].to_i >= MIN_OPEN_INTEREST
      end
      return nil if filtered.empty?

      best = filtered.max_by { |c| c[:volume].to_i }
      ::Derivative.find_by(security_id: best[:security_id].to_s)
    rescue StandardError => e
      Rails.logger.warn("[StrikeSelector] failed for #{index_instrument.symbol_name}: #{e.class} - #{e.message}")
      nil
    end

    private

    def find_next_expiry(_instrument)
      # Placeholder: in practice read from instrument.expiry_list
      (Time.zone.today + 7).to_s
    end

    def normalize_chain(chain)
      return chain if chain.is_a?(Array)
      # Example remap
      return chain[:option_data] if chain.is_a?(Hash) && chain[:option_data].is_a?(Array)

      []
    end
  end
end

# frozen_string_literal: true

require 'bigdecimal'

module Trading
  class StrikeSelector
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
        security_id: instrument.security_id,
        exchange_segment: instrument.exchange_segment,
        interval: '5minute',
        lookback: 5
      )
      last_close = candles.last&.dig(:close)
      last_close && BigDecimal(last_close.to_s)
    end
  end
end
