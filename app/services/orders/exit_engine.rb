# frozen_string_literal: true

module Orders
  # Institutional-grade exit engine architecture for NIFTY/SENSEX options
  class ExitEngine
    def initialize(position:, prices:)
      @position = position
      @prices = Array(prices).map(&:to_f)
      @entry_price = position.entry_price.to_f
      @highest_price = (position.highest_price || @prices.max || @entry_price).to_f
    end

    # Returns the recommended stop loss price
    def recommended_sl
      regime = VolatilityRegimeDetector.new(prices: @prices).regime
      gamma_expanding = GammaDetector.new(prices: @prices).gamma_expanding?
      
      # MFE-based stop
      mfe_stop = MfeExitEngine.new(
        position: @position,
        ltp: @prices.last,
        entry_price: @entry_price,
        highest_price: @highest_price
      ).call

      # Adaptive trailing stop
      trailing_stop = AdaptiveTrailing.new(
        highest: @highest_price,
        regime: regime
      ).stop

      # If gamma is expanding (convex acceleration), we loosen trailing to allow the move to breathe
      if gamma_expanding && profit_pct > 0.20
        # Loosen by 10% extra gap if gamma is expanding
        trailing_stop = (@highest_price * 0.65).round(2)
      end

      # Expiry tightening
      expiry_engine = ExpiryRuleEngine.new(symbol: @position.symbol)
      
      base_stop = [mfe_stop, trailing_stop].compact.max
      
      if expiry_engine.tighten_trailing?
        # Tighten SL to 90% of highest on expiry afternoon
        expiry_stop = (@highest_price * 0.90).round(2)
        [base_stop, expiry_stop].compact.max
      else
        base_stop
      end
    end

    # Returns true if an immediate exit is required (e.g., expiry force exit)
    def force_exit?
      ExpiryRuleEngine.new(symbol: @position.symbol).force_exit?
    end

    private

    def profit_pct
      return 0.0 if @entry_price.zero?
      (@prices.last - @entry_price) / @entry_price
    end
  end
end
