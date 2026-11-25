# frozen_string_literal: true

module Adapters
  module OptionChain
    # Live DhanHQ option-chain adapter.
    # Instrument delegates broker option-chain calls through this adapter.
    class DhanAdapter
      EXPIRY_LIST_TTL = 6.hours

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
      # Expiries change at most weekly but every caller (signal loop, analysers, dashboard) used to pay
      # a rate-limited REST round trip; empty/failed results are not cached so a bad fetch retries.
      # @return [Array, nil]
      def fetch_expiry_list(underlying_scrip:, underlying_seg:)
        key = "dhan/expiry_list/#{underlying_seg}/#{underlying_scrip}"
        cached = Rails.cache.read(key)
        return cached if cached.present?

        fresh = DhanHQ::Models::OptionChain.fetch_expiry_list(underlying_scrip: underlying_scrip, underlying_seg: underlying_seg)
        Rails.cache.write(key, fresh, expires_in: EXPIRY_LIST_TTL) if fresh.present?
        fresh
      end
    end
  end
end
