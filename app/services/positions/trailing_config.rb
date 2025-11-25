# frozen_string_literal: true

module Positions
  # Trailing configuration for position management
  # Defines peak drawdown threshold and tiered SL offset mapping
  # Based on profit percentage thresholds
  module TrailingConfig
    # Peak drawdown percentage threshold for immediate exit
    # If peak_profit_pct - current_profit_pct >= PEAK_DRAWDOWN_PCT, exit immediately
    PEAK_DRAWDOWN_PCT = 5.0

    # Tiered SL offset configuration
    # Each tier maps a profit percentage threshold to an SL offset percentage
    # SL offset is relative to entry price:
    #   - Negative values: SL below entry (e.g., -15% means SL = entry * 0.85)
    #   - Zero: SL at entry (breakeven)
    #   - Positive values: SL above entry (e.g., +10% means SL = entry * 1.10)
    TIERS = [
      { threshold_pct: 5.0, sl_offset_pct: -15.0 },
      { threshold_pct: 10.0, sl_offset_pct: -5.0 },
      { threshold_pct: 15.0, sl_offset_pct: 0.0 },
      { threshold_pct: 25.0, sl_offset_pct: 10.0 },
      { threshold_pct: 40.0, sl_offset_pct: 20.0 },
      { threshold_pct: 60.0, sl_offset_pct: 30.0 },
      { threshold_pct: 80.0, sl_offset_pct: 40.0 },
      { threshold_pct: 120.0, sl_offset_pct: 60.0 }
    ].freeze

    class << self
      # Get SL offset percentage for a given profit percentage
      # @param profit_pct [Float] Current profit percentage (e.g., 25.0 for 25%)
      # @return [Float] SL offset percentage for the tier that matches profit_pct
      # @example
      #   sl_offset_for(7.5)  # => -15.0 (below 10% threshold, uses 5% tier)
      #   sl_offset_for(12.0) # => -5.0  (above 10% threshold, uses 10% tier)
      #   sl_offset_for(20.0) # => 0.0   (above 15% threshold, uses 15% tier)
      #   sl_offset_for(50.0) # => 20.0   (above 40% threshold, uses 40% tier)
      def sl_offset_for(profit_pct)
        return TIERS.first[:sl_offset_pct] if profit_pct < TIERS.first[:threshold_pct]

        # Find the highest tier that the profit_pct has reached
        matching_tier = TIERS.reverse.find { |tier| profit_pct >= tier[:threshold_pct] }
        return matching_tier[:sl_offset_pct] if matching_tier

        # If profit exceeds highest tier, use highest tier's offset
        TIERS.last[:sl_offset_pct]
      end

      # Get all tiers (for testing/debugging)
      # @return [Array<Hash>] Copy of TIERS array
      def tiers
        TIERS.dup
      end

      # Check if profit percentage triggers peak drawdown exit
      # @param peak_profit_pct [Float] Peak profit percentage achieved
      # @param current_profit_pct [Float] Current profit percentage
      # @return [Boolean] True if drawdown >= PEAK_DRAWDOWN_PCT
      def peak_drawdown_triggered?(peak_profit_pct, current_profit_pct)
        return false unless peak_profit_pct && current_profit_pct

        drawdown = peak_profit_pct - current_profit_pct
        drawdown >= PEAK_DRAWDOWN_PCT
      end

      def peak_drawdown_active?(profit_pct:, current_sl_offset_pct:)
        config = begin
          AlgoConfig.fetch[:risk] || {}
        rescue StandardError
          {}
        end

        required_profit = config.fetch(:peak_drawdown_activation_profit_pct, 25.0).to_f
        required_sl_offset = config.fetch(:peak_drawdown_activation_sl_offset_pct, 10.0).to_f

        profit_pct.to_f >= required_profit && current_sl_offset_pct.to_f >= required_sl_offset
      end

      # Calculate SL price based on entry price and profit percentage
      # @param entry_price [Float] Entry price
      # @param profit_pct [Float] Current profit percentage
      # @return [Float] Calculated SL price (rounded to 2 decimal places)
      def calculate_sl_price(entry_price, profit_pct)
        return nil unless entry_price&.positive?

        offset_pct = sl_offset_for(profit_pct)
        (entry_price * (1.0 + (offset_pct / 100.0))).round(2)
      end
    end
  end
end
