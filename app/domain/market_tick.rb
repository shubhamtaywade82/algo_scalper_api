# frozen_string_literal: true

# Immutable market tick used as the domain boundary for market-data reads.
MarketTick = Data.define(:segment, :security_id, :ltp, :timestamp, :oi, :oi_change, :bid, :ask, :bid_qty, :ask_qty, :volume, :prev_close)
