# frozen_string_literal: true

module Orders
  # Central analyzer for order-related decisions, specifically trailing exits
  class Analyzer
    def initialize(tracker:, ltp:, prices: nil, peak_profit_pct: nil)
      @tracker = tracker
      @ltp = ltp.to_f
      @prices = Array(prices || [ltp])
      @entry_price = tracker.entry_price.to_f
      @peak_profit_pct = peak_profit_pct || (tracker.high_water_mark_pnl.to_f / (@entry_price * tracker.quantity.to_f))
      @highest_price = @entry_price * (1.0 + @peak_profit_pct)
    end

    # Returns the recommended SL price based on institutional integrated ExitEngine
    def recommended_sl
      prices = @prices.any? ? @prices : [@ltp]
      
      # Use the institutional ExitEngine wrapper
      exit_engine = Orders::ExitEngine.new(
        position: @tracker,
        prices: prices
      )
      
      # Force exit trigger (SL above current price)
      return (@ltp * 1.1).round(2) if exit_engine.force_exit?

      # Integrated signals: MFE, Volatility Regime, Gamma Expansion, Adaptive Trailing, Expiry Rules
      base_sl = exit_engine.recommended_sl

      # Cross-check with GammaTrailingEngine for exhaustive state management
      gamma_engine = Orders::GammaTrailingEngine.new(
        position: @tracker,
        prices: prices,
        entry_price: @entry_price,
        highest_price: @highest_price
      )
      gamma_sl = gamma_engine.call

      # Capture the most conservative (highest) protection level
      [base_sl, gamma_sl].compact.max
    end
  end
end
