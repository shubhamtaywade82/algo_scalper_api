# frozen_string_literal: true

module Orders
  class Gateway
    # ----------- PRIMARY EXIT METHOD ----------
    def exit_market(tracker)
      raise NotImplementedError, "#{self.class} must implement exit_market"
    end

    # ----------- ENTRY (BUY/SELL) -------------
    def place_market(side:, segment:, security_id:, qty:, meta: {})
      raise NotImplementedError, "#{self.class} must implement place_market"
    end

    # ----------- POSITION SNAPSHOT -------------
    def position(segment:, security_id:)
      raise NotImplementedError, "#{self.class} must implement position"
    end

    # ----------- WALLET ------------------------
    def wallet_snapshot
      raise NotImplementedError, "#{self.class} must implement wallet_snapshot"
    end

    # optional
    def on_tick(segment:, security_id:, ltp:)
      nil
    end
  end
end
