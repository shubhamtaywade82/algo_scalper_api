# frozen_string_literal: true

module Api
  class DepthController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      symbol = params[:symbol] || 'NIFTY'
      depth = fetch_depth(symbol)

      render json: depth
    end

    private

    def fetch_depth(symbol)
      if %w[NIFTY BANKNIFTY SENSEX].include?(symbol.upcase)
        begin
          analyzer = Options::DerivativeChainAnalyzer.new(index_key: symbol.upcase)
          spot = analyzer.spot_ltp
          expiry = analyzer.find_nearest_expiry
          if spot&.positive? && expiry
            increment = if spot >= 50_000
100
                        else
(spot >= 10_000 ? 50 : 25)
                        end
            atm = (spot / increment).round * increment
            contract = Derivative.options.find_by(underlying_symbol: symbol.upcase, expiry_date: expiry, strike_price: atm, option_type: 'CE')
            if contract
              depth = try_dhan_quote(contract)
              return depth if depth
              return try_redis_depth(contract) || empty_depth("#{symbol} ATM CE")
            end
          end
        rescue StandardError => e
          Rails.logger.warn("[DepthController] Failed to resolve ATM CE option for #{symbol}: #{e.message}")
        end
      end

      instrument = Instrument.find_by(symbol_name: symbol.upcase, segment: 'index')
      return empty_depth(symbol) unless instrument

      depth = try_dhan_quote(instrument)
      return depth if depth

      try_redis_depth(instrument) || empty_depth(symbol)
    end

    def try_dhan_quote(instrument)
      exch_enum = { instrument.exchange_segment => [instrument.security_id.to_i] }
      response = DhanHQ::Models::MarketFeed.quote(exch_enum)

      return nil unless response.is_a?(Hash) && response['status'] == 'success'

      quote_data = response.dig('data', instrument.exchange_segment, instrument.security_id.to_s)
      return nil unless quote_data

      raw_depth = quote_data['depth'] || quote_data[:depth]
      return nil unless raw_depth

      bids = (raw_depth['buy'] || raw_depth[:buy] || []).map { |l| map_depth_level(l) }
      asks = (raw_depth['sell'] || raw_depth[:sell] || []).map { |l| map_depth_level(l) }

      {
        symbol: instrument.symbol_name,
        bid: bids,
        ask: asks,
        totalBidQty: bids.sum { |b| b[:qty] },
        totalAskQty: asks.sum { |a| a[:qty] }
      }
    rescue StandardError => e
      Rails.logger.debug("[DepthController] DhanHQ quote failed: #{e.message}")
      nil
    end

    def map_depth_level(level)
      {
        price: (level['price'] || level[:price]).to_f,
        qty: (level['quantity'] || level[:quantity]).to_i,
        orders: (level['orders'] || level[:orders]).to_i
      }
    end

    def try_redis_depth(instrument)
      cached = Validators::MarketDataCache.depth_snapshot(instrument.security_id)
      return nil unless cached

      {
        symbol: instrument.symbol_name,
        bid: [{ price: cached[:best_bid].to_f, qty: cached[:best_bid_qty].to_i, orders: 0 }],
        ask: [{ price: cached[:best_ask].to_f, qty: cached[:best_ask_qty].to_i, orders: 0 }],
        totalBidQty: cached[:best_bid_qty].to_i,
        totalAskQty: cached[:best_ask_qty].to_i
      }
    end

    def empty_depth(symbol)
      { symbol: symbol, bid: [], ask: [], totalBidQty: 0, totalAskQty: 0 }
    end
  end
end
