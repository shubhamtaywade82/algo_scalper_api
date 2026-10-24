# frozen_string_literal: true

module Trading
  class LotCalculator
    class UnsupportedInstrumentError < StandardError; end

    LOT_SIZES = {
      'NIFTY' => 75,
      'BANKNIFTY' => 15,
      'SENSEX' => 10
    }.freeze

    class << self
      # Weekly expiry only is assumed upstream (no dynamic sizing here).
      #
      # Sources: the India index registry (config-driven) and the static LOT_SIZES
      # floor. When both define a symbol they must AGREE — a silent
      # registry-wins policy would let a stale registry row mis-size every order.
      #
      # @param symbol [String, Symbol]
      # @return [Integer]
      # @raise [Trading::LotCalculator::UnsupportedInstrumentError] when neither source defines the symbol
      # @raise [Errors::InvariantViolation] when the two sources disagree
      def lot_size_for(symbol)
        key = symbol.to_s.strip.upcase
        registry_lot = IndiaIndexRegistry.for_key(key)&.dig(:lot)
        static_lot = LOT_SIZES[key]

        if registry_lot && static_lot && registry_lot != static_lot
          raise Errors::InvariantViolation,
                "lot size sources disagree for #{key}: india_index_registry=#{registry_lot.inspect} vs LOT_SIZES=#{static_lot.inspect}"
        end

        lot = registry_lot || static_lot
        raise UnsupportedInstrumentError, "Unsupported instrument: #{symbol}" unless lot

        lot
      end
    end
  end
end
