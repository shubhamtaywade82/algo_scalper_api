# frozen_string_literal: true

module Trading
  # Lot size comes from the exchange via the instrument master (InstrumentsImportJob
  # syncs Dhan's scrip CSV daily). NSE/BSE revise lots a few times a year; the old
  # hard-coded 75/15/10 went stale and mis-sized every BANKNIFTY entry by 2x.
  class LotCalculator
    class UnsupportedInstrumentError < StandardError; end

    CACHE_TTL = 1.hour

    class << self
      # @param symbol [String, Symbol] underlying index key, e.g. "NIFTY"
      # @return [Integer] lot size of the nearest live option contract
      # @raise [UnsupportedInstrumentError] when the master has no live contract —
      #   fail closed rather than size an order with a guessed lot.
      def lot_size_for(symbol)
        key = symbol.to_s.strip.upcase
        lot = Rails.cache.fetch("lot_size:#{key}:#{Time.zone.today}", expires_in: CACHE_TTL, skip_nil: true) do
          nearest_contract_lot(key)
        end
        return lot if lot&.positive?

        raise UnsupportedInstrumentError,
              "No live option contract with a lot size for #{key} in the instrument master — run InstrumentsImportJob"
      end

      private

      def nearest_contract_lot(key)
        Instrument.options
                  .where(underlying_symbol: key, expiry_date: Time.zone.today..)
                  .where.not(lot_size: nil)
                  .order(:expiry_date)
                  .pick(:lot_size)
      end
    end
  end
end
