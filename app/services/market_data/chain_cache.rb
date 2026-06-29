# frozen_string_literal: true

module AlgoScalper
  module MarketData
    class ChainCache
      def initialize(atm_range: 5)
        @atm_range = atm_range
        @chains = Concurrent::Map.new
        @callbacks = []
      end

      def put(symbol, expiry, chain)
        key = "#{symbol}:#{expiry}"
        @chains[key] = chain.merge(
          symbol: symbol,
          expiry: expiry,
          received_at: Time.now,
          atm_strike: find_atm(chain)
        )
        @callbacks.each { |cb| cb.call(chain) }
      end

      def get(symbol, expiry)
        @chains["#{symbol}:#{expiry}"]
      end

      def last_refresh(symbol, expiry)
        @chains["#{symbol}:#{expiry}"]&.dig(:received_at) || Time.at(0)
      end

      def on_update(&block)
        @callbacks << block
      end

      def atm_strike(symbol, expiry)
        get(symbol, expiry)&.dig(:atm_strike)
      end

      def option(symbol, expiry, strike, type)
        chain = get(symbol, expiry)
        return nil unless chain

        chain.dig(:options, strike.to_s, type.to_s.upcase)
      end

      private

      def find_atm(chain)
        spot = chain[:spot] || chain[:underlying_value]
        return nil unless spot

        strikes = chain[:options]&.keys&.map(&:to_f)&.sort
        return nil unless strikes&.any?

        strikes.min_by { |s| (s - spot).abs }
      end
    end
  end
end