# frozen_string_literal: true

module Investing
  module Portfolios
    # Read-only market-data facade (TDD §6.3). One method:
    #   prices_for(instrument_ids) -> Hash{Integer=>BigDecimal}
    #
    # Production resolution order per instrument:
    #   1. latest tick from the shared Live::RedisTickCache (LTP), else
    #   2. omitted — the Valuer's stale-price rule falls back to the
    #      holding's stored last_price (long-horizon domain is stale-tolerant).
    #
    # NEVER raises on missing prices — it omits the key. In tests the whole
    # source is stubbed or a custom resolver callable is injected.
    class PriceSource
      # @param resolver [#call, nil] optional (instrument) => price; injected
      #        in tests. Defaults to the Redis tick cache.
      def initialize(resolver: nil)
        @resolver = resolver || default_resolver
      end

      # @param instrument_ids [Array<Integer>]
      # @return [Hash{Integer=>BigDecimal}] only instruments with a resolvable price
      def prices_for(instrument_ids)
        Instrument.where(id: instrument_ids).each_with_object({}) do |instrument, out|
          price = safe_resolve(instrument)
          out[instrument.id] = price unless price.nil?
        end
      end

      private

      attr_reader :resolver

      def safe_resolve(instrument)
        raw = resolver.call(instrument)
        return nil if raw.nil? || (raw.respond_to?(:zero?) && raw.zero?)

        BigDecimal(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def default_resolver
        lambda { |instrument|
          tick = tick_cache.fetch_tick(instrument.segment, instrument.security_id)
          tick[:ltp] || tick[:last_price] || tick[:last_traded_price]
        }
      end

      def tick_cache
        @tick_cache ||= Live::RedisTickCache.new
      end
    end
  end
end
