# frozen_string_literal: true

module AlgoScalper
  module MarketData
    class OptionChainFetcher
      RATE_LIMIT = 1.0 # seconds between calls
      @@last_fetch = Concurrent::Map.new

      def self.fetch(symbol, expiry, &block)
        return if rate_limited?(symbol, expiry)

        @@last_fetch["#{symbol}:#{expiry}"] = Time.now

        Thread.new do
          begin
            inst = DhanHQ::Models::Instrument.find("IDX_I", symbol)
            unless inst
              block.call(nil)
              return
            end

            chain = inst.option_chain(expiry: expiry)
            block.call(normalize_chain(chain, symbol, expiry))
          rescue => e
            AlgoScalper.logger.error("Option chain fetch failed: #{e.message}")
            block.call(nil)
          end
        end
      end

      def self.rate_limited?(symbol, expiry)
        last = @@last_fetch["#{symbol}:#{expiry}"]
        return false unless last

        Time.now - last < RATE_LIMIT
      end

      def self.normalize_chain(raw, symbol, expiry)
        return nil unless raw && raw[:oc]

        spot = raw[:last_price] || raw[:spot] || raw[:underlying_value]
        options = {}

        raw[:oc].each do |strike_str, data|
          strike = strike_str.to_f
          next if (strike - spot).abs > 500 # Filter far strikes

          ce = normalize_option(data["ce"] || data[:ce], strike, "CE", spot)
          pe = normalize_option(data["pe"] || data[:pe], strike, "PE", spot)

          options[strike] = { ce: ce, pe: pe }.compact
        end

        {
          symbol: symbol,
          expiry: expiry,
          spot: spot,
          options: options,
          atm_strike: find_atm(options, spot)
        }
      end

      def self.normalize_option(opt, strike, type, spot)
        return nil unless opt && opt["last_price"].to_f > 0

        greeks = opt["greeks"] || opt[:greeks] || {}

        {
          symbol: opt["symbol"],
          security_id: opt["security_id"],
          strike: strike,
          type: type,
          ltp: opt["last_price"].to_f,
          bid: opt["top_bid_price"].to_f,
          ask: opt["top_ask_price"].to_f,
          volume: opt["volume"].to_i,
          oi: opt["oi"].to_i,
          oi_change: opt["oi_change"].to_i,
          iv: opt["implied_volatility"].to_f,
          delta: greeks["delta"].to_f,
          gamma: greeks["gamma"].to_f,
          theta: greeks["theta"].to_f,
          vega: greeks["vega"].to_f,
          spread_pct: calculate_spread(opt, spot)
        }
      end

      def self.calculate_spread(opt, spot)
        bid = opt["top_bid_price"].to_f
        ask = opt["top_ask_price"].to_f
        return 0.0 if bid.zero? || ask.zero?

        ((ask - bid) / ask) * 100
      end

      def self.find_atm(options, spot)
        return nil unless spot && options.any?

        options.keys.min_by { |s| (s - spot).abs }
      end
    end
  end
end