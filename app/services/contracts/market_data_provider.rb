# frozen_string_literal: true

module Contracts
  # Formal interface for market data access.
  # Strategies and services depend on this contract, not concrete implementations.
  # PRD §114: One of the 9 core interfaces the system reduces to.
  module MarketDataProvider
    def ltp(segment:, security_id:)
      raise NotImplementedError, "#{self.class} must implement ltp"
    end

    def tick(segment:, security_id:)
      raise NotImplementedError, "#{self.class} must implement tick"
    end

    def bid_ask(segment:, security_id:)
      raise NotImplementedError, "#{self.class} must implement bid_ask"
    end

    def candles(instrument_or_sid, timeframe:, count: 100)
      raise NotImplementedError, "#{self.class} must implement candles"
    end

    def subscribe(segment:, security_id:)
      raise NotImplementedError, "#{self.class} must implement subscribe"
    end
  end
end
