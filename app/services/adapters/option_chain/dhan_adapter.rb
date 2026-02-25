# frozen_string_literal: true

module Adapters
  module OptionChain
    # Live DhanHQ option-chain adapter.
    # Instrument delegates broker option-chain calls through this adapter.
    class DhanAdapter
      # Fetch option-chain data for an underlying and expiry.
      # @return [Hash, nil]
      def fetch_chain(underlying_scrip:, underlying_seg:, expiry:)
        DhanHQ::Models::OptionChain.fetch(
          underlying_scrip: underlying_scrip,
          underlying_seg: underlying_seg,
          expiry: expiry
        )
      end

      # Fetch available expiry list for an underlying.
      # @return [Array, nil]
      def fetch_expiry_list(underlying_scrip:, underlying_seg:)
        DhanHQ::Models::OptionChain.fetch_expiry_list(
          underlying_scrip: underlying_scrip,
          underlying_seg: underlying_seg
        )
      end
    end
  end
end
