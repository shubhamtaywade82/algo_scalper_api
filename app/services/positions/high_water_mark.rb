# frozen_string_literal: true

module Positions
  # High Water Mark (HWM) tracking and calculation helper
  # Provides utilities for trailing stop calculations and HWM-based exits
  class HighWaterMark
    # Calculate trailing stop threshold based on HWM
    # @param hwm [Float] High water mark PnL
    # @param drop_pct [Float] Percentage drop from HWM to trigger (e.g., 0.20 for 20%)
    # @return [Float] Trailing stop threshold
    def self.trailing_threshold(hwm, drop_pct)
      return 0.0 unless hwm&.positive? && drop_pct&.positive?

      hwm * (1.0 - drop_pct)
    end

    # Check if current PnL has dropped below trailing threshold
    # @param current_pnl [Float] Current PnL
    # @param hwm [Float] High water mark PnL
    # @param drop_pct [Float] Percentage drop from HWM to trigger
    # @return [Boolean] True if trailing stop should trigger
    def self.trailing_triggered?(current_pnl, hwm, drop_pct)
      return false unless hwm&.positive? && current_pnl

      threshold = trailing_threshold(hwm, drop_pct)
      current_pnl <= threshold
    end

    # Calculate HWM-based exit price for long positions
    # @param entry_price [Float] Entry price
    # @param hwm_pnl [Float] High water mark PnL (in rupees)
    # @param quantity [Integer] Position quantity
    # @return [Float] Exit price based on HWM
    def self.hwm_exit_price(entry_price, hwm_pnl, quantity)
      return nil unless entry_price&.positive? && hwm_pnl && quantity&.positive?

      hwm_price = entry_price + (hwm_pnl / quantity.to_f)
      hwm_price.round(2)
    end

    # Calculate percentage gain from entry to HWM
    # @param entry_price [Float] Entry price
    # @param hwm_price [Float] High water mark price
    # @return [Float] Percentage gain
    def self.hwm_gain_pct(entry_price, hwm_price)
      return 0.0 unless entry_price&.positive? && hwm_price&.positive?

      ((hwm_price - entry_price) / entry_price * 100.0).round(4)
    end

    # Calculate drawdown from HWM
    # @param current_pnl [Float] Current PnL
    # @param hwm [Float] High water mark PnL
    # @return [Float] Drawdown percentage (0.0 to 1.0)
    def self.drawdown_from_hwm(current_pnl, hwm)
      return 0.0 unless hwm&.positive? && current_pnl

      if current_pnl >= hwm
        0.0
      else
        ((hwm - current_pnl) / hwm).round(4)
      end
    end

    # Check if position should lock breakeven based on HWM
    # @param hwm_pnl [Float] High water mark PnL
    # @param min_profit_for_lock [Float] Minimum profit required to lock breakeven
    # @return [Boolean] True if breakeven should be locked
    def self.should_lock_breakeven?(hwm_pnl, min_profit_for_lock)
      return false unless hwm_pnl && min_profit_for_lock

      hwm_pnl >= min_profit_for_lock
    end

    # Calculate trailing stop price based on HWM
    # @param entry_price [Float] Entry price
    # @param hwm_price [Float] High water mark price
    # @param trail_pct [Float] Trailing percentage (e.g., 0.20 for 20% from HWM)
    # @return [Float] Trailing stop price
    def self.trailing_stop_price(entry_price, hwm_price, trail_pct)
      return nil unless entry_price&.positive? && hwm_price&.positive? && trail_pct&.positive?

      # Trailing stop is trail_pct below HWM price
      stop_price = hwm_price * (1.0 - trail_pct)
      # But never below entry (for long positions)
      [stop_price, entry_price].max.round(2)
    end
  end
end
