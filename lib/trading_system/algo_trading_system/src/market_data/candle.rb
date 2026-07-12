# frozen_string_literal: true

module MarketData
  # Value object for candle data
  Candle = Data.define(
    :symbol,
    :timestamp,
    :open,
    :high,
    :low,
    :close,
    :volume,
    :timeframe
  )
end
