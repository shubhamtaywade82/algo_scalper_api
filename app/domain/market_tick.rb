# frozen_string_literal: true

# Immutable market tick used as the domain boundary for market-data reads.
MarketTick = Data.define(:segment, :security_id, :ltp, :timestamp, :oi, :oi_change,
                         :bid, :ask, :bid_qty, :ask_qty, :volume, :prev_close) do
  def initialize(segment:, security_id:, ltp:, timestamp:, oi: 0, oi_change: 0,
                 bid: nil, ask: nil, bid_qty: 0, ask_qty: 0, volume: 0, prev_close: nil)
    super(segment: segment, security_id: security_id, ltp: ltp, timestamp: timestamp,
          oi: oi, oi_change: oi_change, bid: bid, ask: ask, bid_qty: bid_qty,
          ask_qty: ask_qty, volume: volume, prev_close: prev_close)
  end
end
