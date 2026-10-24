# frozen_string_literal: true

module Risk
  # Central helper for profit-aware decisions (MFE-based trailing, exit outcome classification).
  # Keeps math in one place so both RiskManager and ExitEngine can use the same semantics.
  class ProfitManager
    include Singleton

    # Classify exit based on final PnL percentage in decimal form (0.12 = 12%).
    # Returns one of: 'profit', 'loss', 'breakeven'.
    def classify_exit(final_pnl_pct_decimal)
      return 'profit' if final_pnl_pct_decimal.to_f.positive?
      return 'loss' if final_pnl_pct_decimal.to_f.negative?

      'breakeven'
    end

    # Compute peak profit pct (MFE) from tracker + snapshot (Redis).
    # Returns decimal fraction (e.g., 0.25 for 25%) or nil.
    def peak_profit_pct_for(tracker, snapshot)
      hwm = snapshot[:hwm_pnl]
      return nil unless hwm&.positive?

      entry_price = tracker.entry_price
      quantity = tracker.quantity
      return nil unless entry_price && quantity&.positive?

      buy_value = entry_price * quantity
      return nil unless buy_value.positive?

      (hwm / buy_value).to_f
    end

    # Given a peak profit pct (decimal) and adaptive tiers config, return allowed drawdown.
    # Delegates to Positions::TrailingConfig.adaptive_drawdown_for_peak to keep logic consistent.
    def allowed_drawdown_for_peak(peak_profit_pct, adaptive_tiers)
      return nil unless peak_profit_pct && adaptive_tiers

      Positions::TrailingConfig.adaptive_drawdown_for_peak(peak_profit_pct, adaptive_tiers)
    end
  end
end

