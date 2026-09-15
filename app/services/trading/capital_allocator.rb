# frozen_string_literal: true

module Trading
  class CapitalAllocator
    # Test-env-only legacy ceiling (see max_capital_per_trade carve-out).
    TEST_FALLBACK_MAX_CAPITAL_PER_TRADE = 30_000.0

    class << self
      # Pure function: computes max lots given premium, lot size and permission cap.
      #
      # Returns 0 lots only as a DOCUMENTED outcome: an input that is not a
      # positive finite number means the trade cannot be sized (the entry is
      # blocked upstream). It is never used to swallow an unexpected error.
      #
      # @param premium [Numeric]
      # @param lot_size [Integer]
      # @param permission_cap [Integer]
      # @return [Integer] lots (>= 0)
      def max_lots(premium:, lot_size:, permission_cap:)
        premium_f = premium.to_f
        lot_i = lot_size.to_i
        cap_i = permission_cap.to_i

        return 0 unless premium_f.finite? && premium_f.positive? && lot_i.positive? && cap_i.positive?

        lots_by_capital = (max_capital_per_trade / (premium_f * lot_i)).floor
        [lots_by_capital, cap_i].min
      end

      # Hard ceiling on capital deployed per trade. Tracks position_sizing.target_rupees.
      #
      # Error-handling review 2026-09 (wave 2): a missing/invalid target used to
      # silently size positions against a hardcoded ₹30,000 ceiling — if the
      # operator's intended budget differed, every entry was mis-sized with no
      # signal. The budget is now mandatory.
      #
      # Test-env carve-out (same convention as AlgoConfig.run_mode): the spec
      # suite stubs AlgoConfig.fetch with partial hashes; test keeps the legacy
      # ceiling so those stubs stay valid. development/production refuse to guess.
      #
      # @return [Float]
      # @raise [Errors::ConfigurationError] when position_sizing.target_rupees is
      #   missing, non-numeric, non-positive or non-finite
      def max_capital_per_trade
        raw = AlgoConfig.fetch.dig(:position_sizing, :target_rupees)
        target = raw.to_f

        unless raw.present? && target.finite? && target.positive?
          return TEST_FALLBACK_MAX_CAPITAL_PER_TRADE if Rails.env.test?

          raise Errors::ConfigurationError,
                "position_sizing.target_rupees must be a positive number — got #{raw.inspect}; " \
                "refusing to size trades against an assumed capital ceiling"
        end

        target
      end
    end
  end
end
