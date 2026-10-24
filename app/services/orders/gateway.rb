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

    # ----------- WALLET ------------------------
    def wallet_snapshot
      raise NotImplementedError, "#{self.class} must implement wallet_snapshot"
    end

    # ----------- ORDER MANAGEMENT --------------
    def cancel_order(order_id)
      raise NotImplementedError, "#{self.class} must implement cancel_order"
    end

    # PRD §32: modify outstanding order (price, qty, type)
    def modify_order(order_id, params = {})
      raise NotImplementedError, "#{self.class} must implement modify_order"
    end

    # PRD §32: close entire position for an instrument
    def close_position(position)
      exit_market(position)
    end

    # optional
    def on_tick(segment:, security_id:, ltp:)
      nil
    end
  end
end
