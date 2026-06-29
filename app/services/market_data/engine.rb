# frozen_string_literal: true

module AlgoScalper
  module MarketData
    class Engine
      attr_reader :tick_cache, :depth_cache, :chain_cache, :config

      def initialize(config = {})
        @config = {
          indices: %w[NIFTY BANKNIFTY SENSEX],
          atm_range: 5,
          regime_tf: "15m",
          structure_tf: "5m",
          execution_tf: "1m",
          expiry_mode: false
        }.merge(config)

        @tick_cache = TickCache.new
        @depth_cache = DepthCache.new
        @chain_cache = ChainCache.new(atm_range: @config[:atm_range])
        @ws_clients = {}
        @subscriptions = {}
      end

      def start
        connect_market_feed
        connect_market_depth
        connect_order_updates
        warm_up_caches
      end

      def stop
        @ws_clients.each_value(&:disconnect!)
        @ws_clients.clear
      end

      def on_tick(&block)
        @tick_cache.on_tick(&block)
      end

      def on_depth(&block)
        @depth_cache.on_update(&block)
      end

      def on_chain_update(&block)
        @chain_cache.on_update(&block)
      end

      def ltp(segment, security_id)
        @tick_cache.ltp(segment, security_id)
      end

      def depth(segment, security_id)
        @depth_cache.get(segment, security_id)
      end

      def option_chain(symbol, expiry)
        @chain_cache.get(symbol, expiry)
      end

      def subscribe_underlying(segment, security_id)
        @ws_clients[:market_feed]&.subscribe_one(segment: segment, security_id: security_id)
      end

      def subscribe_option(segment, security_id)
        @ws_clients[:market_feed]&.subscribe_one(segment: segment, security_id: security_id)
      end

      def refresh_option_chain(symbol, expiry)
        OptionChainFetcher.fetch(symbol, expiry) do |chain|
          @chain_cache.put(symbol, expiry, chain)
        end
      end

      private

      def connect_market_feed
        @ws_clients[:market_feed] = DhanHQ::WS.connect(mode: :quote) do |tick|
          @tick_cache.put(tick)
          process_option_tick(tick)
        end
      end

      def connect_market_depth
        @ws_clients[:market_depth] = DhanHQ::WS::MarketDepth.connect(symbols: depth_symbols) do |depth|
          @depth_cache.put(depth)
        end
      end

      def connect_order_updates
        @ws_clients[:order_updates] = DhanHQ::WS::Orders.connect do |update|
          PositionManager.instance.on_order_update(update)
        end
      end

      def depth_symbols
        @config[:indices].flat_map do |idx|
          inst = DhanHQ::Models::Instrument.find("IDX_I", idx)
          next unless inst

          strikes = option_strikes_for(inst, inst.ltp[:ltp])
          strikes.map { |s| { symbol: s[:symbol], exchange_segment: s[:segment], security_id: s[:security_id] } }
        end.compact
      end

      def option_strikes_for(inst, spot)
        # Returns ATM ±5 strikes for the index
        chain = inst.option_chain(expiry: nearest_expiry(inst))
        return [] unless chain

        atm = chain.atm_strike
        (atm - 5..atm + 5).map do |strike|
          ce = chain.call(strike)
          pe = chain.put(strike)
          [ce, pe].compact.map { |o| { symbol: o.symbol, segment: o.exchange_segment, security_id: o.security_id } }
        end.flatten
      end

      def nearest_expiry(inst)
        inst.expiry_list&.first
      end

      def process_option_tick(tick)
        return unless option_tick?(tick)

        symbol = underlying_symbol(tick)
        expiry = current_expiry(symbol)
        return unless symbol && expiry

        if should_refresh_chain?(tick)
          refresh_option_chain(symbol, expiry)
        end
      end

      def option_tick?(tick)
        tick[:segment] == "NSE_FNO" && tick[:instrument]&.start_with?("OPT")
      end

      def underlying_symbol(tick)
        # Map option to its index
        case tick[:security_id]
        when /^13/ then "NIFTY"
        when /^25/ then "BANKNIFTY"
        when /^51/ then "SENSEX"
        end
      end

      def current_expiry(symbol)
        inst = DhanHQ::Models::Instrument.find("IDX_I", symbol)
        inst&.expiry_list&.first
      end

      def should_refresh_chain?(tick)
        # Refresh on underlying move > 0.15% or every 1 second
        last_refresh = @chain_cache.last_refresh(symbol, expiry)
        Time.now - last_refresh > 1 || price_move_exceeds?(tick, 0.0015)
      end

      def price_move_exceeds?(tick, threshold)
        # Check if price moved > threshold since last refresh
        false # placeholder
      end

      def warm_up_caches
        @config[:indices].each do |idx|
          inst = DhanHQ::Models::Instrument.find("IDX_I", idx)
          next unless inst

          subscribe_underlying(inst.exchange_segment, inst.security_id)
          expiry = inst.expiry_list&.first
          next unless expiry

          refresh_option_chain(idx, expiry)
        end
      end
    end
  end
end