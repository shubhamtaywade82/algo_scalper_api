# frozen_string_literal: true

# Abstract Gateway interface for order placement and position management
# Implementations: Paper::Gateway (simulated) and Live::Gateway (real orders)
module Orders
  class Gateway
    # Place a MARKET order
    # @param side [String] "buy" or "sell"
    # @param segment [String] Exchange segment (e.g., "NSE_FNO")
    # @param security_id [String] Security ID
    # @param qty [Integer] Quantity
    # @param meta [Hash] Optional metadata
    # @return [Object] Order response (gateway-specific format)
    def place_market(side:, segment:, security_id:, qty:, meta: {})
      raise NotImplementedError, "#{self.class} must implement place_market"
    end

    # Flatten a position (close it completely)
    # @param segment [String] Exchange segment
    # @param security_id [String] Security ID
    # @return [Object] Order response or nil
    def flat_position(segment:, security_id:)
      raise NotImplementedError, "#{self.class} must implement flat_position"
    end

    # Get position snapshot
    # @param segment [String] Exchange segment
    # @param security_id [String] Security ID
    # @return [Hash] {qty:, avg_price:, upnl:, rpnl:, last_ltp:} or nil if no position
    def position(segment:, security_id:)
      raise NotImplementedError, "#{self.class} must implement position"
    end

    # Get wallet snapshot
    # @return [Hash] {cash:, equity:, mtm:, exposure:}
    def wallet_snapshot
      raise NotImplementedError, "#{self.class} must implement wallet_snapshot"
    end

    # Hook for tick updates (paper mode only)
    # @param segment [String] Exchange segment
    # @param security_id [String] Security ID
    # @param ltp [Float] Last traded price
    def on_tick(segment:, security_id:, ltp:)
      # Default: no-op (live gateway doesn't need tick updates)
      nil
    end
  end
end

