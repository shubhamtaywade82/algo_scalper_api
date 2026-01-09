# frozen_string_literal: true

module Trading
  # DirectionGate - HARD direction filter based on market regime.
  #
  # This gate MUST be checked BEFORE:
  # - SMC analysis
  # - AVRZ calculations
  # - Permission resolution
  # - Entry logic
  #
  # RULES (NON-NEGOTIABLE):
  # - :bearish regime + :CE side → BLOCKED (no BUY CE in bearish)
  # - :bullish regime + :PE side → BLOCKED (no BUY PE in bullish)
  # - :neutral regime           → BLOCKED (no directional trades)
  # - All other combinations    → ALLOWED
  #
  # NO OVERRIDES. NO SOFT DOWNGRADES. NO PROBABILISTIC LOGIC.
  #
  class DirectionGate
    VALID_REGIMES = %i[bullish bearish neutral].freeze
    VALID_SIDES = %i[CE PE].freeze

    class << self
      # Check if a trade direction is allowed under the current market regime.
      #
      # @param regime [Symbol] Market regime: :bullish, :bearish, or :neutral
      # @param side [Symbol] Option side: :CE or :PE
      # @return [Boolean] true if trade is allowed, false if BLOCKED
      def allow?(regime:, side:)
        normalized_regime = normalize_regime(regime)
        normalized_side = normalize_side(side)

        # Rule 1: Neutral regime → Block ALL directional trades
        if normalized_regime == :neutral
          log_blocked(side: normalized_side, regime: normalized_regime)
          return false
        end

        # Rule 2: Bearish regime + CE side → Block (no BUY CE in bearish market)
        if normalized_regime == :bearish && normalized_side == :CE
          log_blocked(side: normalized_side, regime: normalized_regime)
          return false
        end

        # Rule 3: Bullish regime + PE side → Block (no BUY PE in bullish market)
        if normalized_regime == :bullish && normalized_side == :PE
          log_blocked(side: normalized_side, regime: normalized_regime)
          return false
        end

        # All other combinations → Allowed
        true
      end

      # Convenience method to check if a trade is blocked (inverse of allow?)
      #
      # @param regime [Symbol] Market regime: :bullish, :bearish, or :neutral
      # @param side [Symbol] Option side: :CE or :PE
      # @return [Boolean] true if trade is BLOCKED, false if allowed
      def blocked?(regime:, side:)
        !allow?(regime: regime, side: side)
      end

      private

      def normalize_regime(regime)
        return :neutral if regime.nil?

        sym = regime.to_s.strip.downcase.to_sym
        VALID_REGIMES.include?(sym) ? sym : :neutral
      end

      def normalize_side(side)
        return nil if side.nil?

        sym = side.to_s.strip.upcase.to_sym
        VALID_SIDES.include?(sym) ? sym : nil
      end

      def log_blocked(side:, regime:)
        Rails.logger.info("[DirectionGate] blocked #{side} in #{regime} regime")
      end
    end
  end
end
