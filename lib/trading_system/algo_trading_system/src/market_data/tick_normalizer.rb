# frozen_string_literal: true

module MarketData
  # Value object for tick data
  Tick = Data.define(
    :symbol,
    :security_id,
    :last_price,
    :last_quantity,
    :average_price,
    :volume,
    :open_interest,
    :timestamp
  )

  # Normalizes raw WebSocket ticks
  class TickNormalizer
    class << self
      def normalize(raw_tick, symbol_map = {}, tick_class = Tick)
        security_id = extract_security_id(raw_tick)
        symbol = symbol_map[security_id] || security_id
        
        tick_class.new(
          symbol: symbol,
          security_id: security_id,
          last_price: extract_float(raw_tick, :LTP),
          last_quantity: extract_int(raw_tick, :LTQ),
          average_price: extract_float(raw_tick, :ATP),
          volume: extract_int(raw_tick, :volume),
          open_interest: extract_int(raw_tick, :OI),
          timestamp: extract_timestamp(raw_tick)
        )
      end

      private

      def extract_security_id(raw)
        raw[:securityId] || raw['securityId']
      end

      def extract_float(raw, key)
        (raw[key] || raw[key.to_s]).to_f
      end

      def extract_int(raw, key)
        (raw[key] || raw[key.to_s]).to_i
      end

      def extract_timestamp(raw)
        ts = raw[:timestamp] || raw['timestamp']
        return Time.now unless ts.is_a?(Numeric)

        Time.at(ts)
      end
    end
  end
end
