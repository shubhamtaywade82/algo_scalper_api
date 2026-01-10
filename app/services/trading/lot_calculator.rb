# frozen_string_literal: true

module Trading
  class LotCalculator
    class UnsupportedInstrumentError < StandardError; end

    LOT_SIZES = {
      'NIFTY' => 65,
      'SENSEX' => 20
    }.freeze

    class << self
      # Weekly expiry only is assumed upstream (no dynamic sizing here).
      #
      # @param symbol [String, Symbol]
      # @return [Integer]
      def lot_size_for(symbol)
        key = symbol.to_s.strip.upcase
        lot = LOT_SIZES[key]
        raise UnsupportedInstrumentError, "Unsupported instrument: #{symbol}" unless lot

        lot
      end
    end
  end
end

