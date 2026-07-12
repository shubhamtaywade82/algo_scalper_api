module BacktestEngine
  module Data
    class InstrumentMetadata
      # DhanHQ security IDs for index historical/options data (IDX_I / NSE_FNO).
      # Verify against https://images.dhan.co/api-data/api-scrip-master.csv if needed.
      SECURITY_IDS = {
        "NIFTY" => "13",
        "BANKNIFTY" => "25",
        "SENSEX" => "1"
      }.freeze

      LOT_SIZES = {
        "NIFTY" => 50,
        "BANKNIFTY" => 15,
        "SENSEX" => 10
      }.freeze

      def self.supported_symbols
        LOT_SIZES.keys
      end

      def self.security_id(symbol)
        key = symbol.to_s.upcase
        SECURITY_IDS.fetch(key) do
          raise ArgumentError, "Unknown symbol: #{symbol}. Supported: #{supported_symbols.join(', ')}"
        end
      end

      def self.lot_size(symbol)
        key = symbol.to_s.upcase
        LOT_SIZES.fetch(key) do
          raise ArgumentError, "Unknown symbol: #{symbol}. Supported: #{supported_symbols.join(', ')}"
        end
      end
    end
  end
end

