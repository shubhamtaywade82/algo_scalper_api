# frozen_string_literal: true

module Orders
  class Gateway
    # ----------- PRIMARY EXIT METHOD ----------
    def exit_market(tracker, client_order_id: nil)
      raise NotImplementedError, "#{self.class} must implement exit_market"
    end

    # ----------- ENTRY (BUY/SELL) -------------
    def place_market(side:, segment:, security_id:, qty:, meta: {})
      raise NotImplementedError, "#{self.class} must implement place_market"
    end

    # IOC limit order — fills immediately or cancels (thin-book fallback)
    def place_ioc_limit(side:, segment:, security_id:, qty:, price:, meta: {})
      raise NotImplementedError, "#{self.class} must implement place_ioc_limit"
    end

    # ----------- WALLET ------------------------
    def wallet_snapshot
      raise NotImplementedError, "#{self.class} must implement wallet_snapshot"
    end

    # ----------- ORDER MANAGEMENT --------------
    def cancel_order(order_id)
      raise NotImplementedError, "#{self.class} must implement cancel_order"
    end

    # optional
    def on_tick(segment:, security_id:, ltp:)
      nil
    end
  end
end
