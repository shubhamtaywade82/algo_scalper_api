# frozen_string_literal: true

module Positions
  # Calculates dynamic ATR Chandelier trailing stop loss prices with profit acceleration.
  class HybridATRCalculator
    DEFAULT_BASE_MULTIPLIER = 2.0
    DEFAULT_ACTIVATION_PROFIT_PCT = 0.15 # 15%
    DEFAULT_MIN_SL_OFFSET_PCT = -0.15 # -15% from entry

    class << self
      def calculate_sl_price(current_price:, entry_price:, peak_price:, current_profit_pct:, atr_value:, options: {})
        return nil unless current_price&.positive? && entry_price&.positive? && peak_price&.positive?
        return nil if atr_value.nil? || atr_value <= 0

        activation_profit_pct = options[:activation_profit_pct] || DEFAULT_ACTIVATION_PROFIT_PCT
        return nil if current_profit_pct.to_f < activation_profit_pct.to_f

        base_multiplier = options[:base_multiplier] || DEFAULT_BASE_MULTIPLIER
        min_sl_offset_pct = options[:min_sl_offset_pct] || DEFAULT_MIN_SL_OFFSET_PCT

        accel_factor = acceleration_factor(current_profit_pct.to_f)
        effective_multiplier = base_multiplier * accel_factor

        # Chandelier Exit: Peak High - (ATR * Effective Multiplier)
        chandelier_sl = peak_price - (atr_value * effective_multiplier)

        # Floor SL: Entry * (1 + min_sl_offset_pct)
        floor_sl = entry_price * (1.0 + min_sl_offset_pct)

        # Stop loss can only move up, capped at current price
        calculated_sl = [chandelier_sl, floor_sl].max
        [calculated_sl, current_price].min.round(2)
      end

      def acceleration_factor(profit_pct)
        case profit_pct
        when 0.50..Float::INFINITY
          0.50
        when 0.30...0.50
          0.70
        when 0.15...0.30
          0.85
        else
          1.00
        end
      end
    end
  end
end
