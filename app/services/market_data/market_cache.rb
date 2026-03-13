# frozen_string_literal: true

module MarketData
  # Practical, lean market data cache for NIFTY/SENSEX options
  # Compliance with Phase 1 naming conventions
  class MarketCache
    def self.write(key, value)
      Rails.cache.write(key, value, expires_in: 5.minutes)
    end

    def self.read(key)
      Rails.cache.read(key)
    end

    def self.update_ltp(symbol, price, is_index: false)
      prefix = is_index ? 'index' : 'option'
      key = "ltp:#{prefix}:#{symbol.to_s.upcase}"
      write(key, price.to_f)
    end

    def self.ltp(symbol, is_index: false)
      prefix = is_index ? 'index' : 'option'
      read("ltp:#{prefix}:#{symbol.to_s.upcase}")
    end

    def self.update_option_data(symbol, data)
      # data: { oi: 123, volume: 456, ltp: 78.9 }
      write("oi:option:#{symbol.to_s.upcase}", data[:oi]) if data[:oi]
      write("volume:option:#{symbol.to_s.upcase}", data[:volume]) if data[:volume]
      update_ltp(symbol, data[:ltp]) if data[:ltp]
    end
  end
end
