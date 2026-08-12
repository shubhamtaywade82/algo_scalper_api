# frozen_string_literal: true

module Trading
  class CapitalAllocator
    # Fallback ceiling when position_sizing.target_rupees is unset in config.
    DEFAULT_MAX_CAPITAL_PER_TRADE = 30_000.0

    class << self
      # Pure function: computes max lots given premium, lot size and permission cap.
      #
      # @param premium [Numeric]
      # @param lot_size [Integer]
      # @param permission_cap [Integer]
      # @return [Integer] lots (>= 0)
      def max_lots(premium:, lot_size:, permission_cap:)
        premium_f = premium.to_f
        lot_i = lot_size.to_i
        cap_i = permission_cap.to_i

        return 0 unless premium_f.positive? && lot_i.positive? && cap_i.positive?

        lots_by_capital = (max_capital_per_trade / (premium_f * lot_i)).floor
        [lots_by_capital, cap_i].min
      rescue StandardError
        0
      end

      # Hard ceiling on capital deployed per trade. Tracks position_sizing.target_rupees
      # so this stays aligned with the actual risk budget instead of a stale flat number.
      def max_capital_per_trade
        target = AlgoConfig.fetch.dig(:position_sizing, :target_rupees).to_f
        target.positive? ? target : DEFAULT_MAX_CAPITAL_PER_TRADE
      end
    end
  end
end
