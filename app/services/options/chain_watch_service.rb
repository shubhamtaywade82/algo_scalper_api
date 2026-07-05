# frozen_string_literal: true

module Options
  class ChainWatchService
    STRIKE_WINDOW = 5
    POLL_INTERVAL_SECONDS = 4
    BROADCAST_INTERVAL_SECONDS = 1

    def initialize(index_key:)
      @index_key = index_key.to_s.upcase
      @index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == @index_key }
      raise "unknown_index:#{@index_key}" unless @index_cfg

      @running = false
      @mutex = Mutex.new
      @thread = nil
      @snapshot = { index_key: @index_key, spot: nil, atm_strike: nil, expiry: nil, legs: [], chain_stale: true, updated_at: nil }
      @subscribed_legs = []
    end

    def running?
      @running
    end

    def snapshot
      @mutex.synchronize { @snapshot.dup }
    end

    def start!
      return if running?

      @running = true
      @thread = Thread.new { run_loop }
      @thread.name = "chain-watch-#{@index_key.downcase}" if @thread.respond_to?(:name=)
    end

    def stop!
      @running = false
      @thread&.kill
      @thread&.join(1)
      @thread = nil
      unsubscribe_current_legs!
    end

    def resolve_atm_legs(spot:, expiry:)
      increment = strike_increment_for(spot)
      atm = (spot / increment).round * increment
      strikes = (-STRIKE_WINDOW..STRIKE_WINDOW).map { |offset| atm + (offset * increment) }.select(&:positive?)

      Derivative.options
                .where(underlying_symbol: @index_key, expiry_date: expiry, strike_price: strikes)
                .where.not("security_id LIKE 'TEST_%'")
                .map do |d|
        {
          strike: d.strike_price.to_f, type: d.option_type, security_id: d.security_id.to_s,
          segment: d.exchange_segment, lot_size: d.lot_size.to_i,
          ltp: nil, oi: nil, oi_change: nil, iv: nil, delta: nil, gamma: nil, theta: nil, vega: nil,
          bid: nil, ask: nil, feed_stale: true
        }
      end
    end

    private

    def run_loop
      last_poll_at = Time.at(0)

      while running?
        begin
          analyzer = Options::DerivativeChainAnalyzer.new(index_key: @index_key)
          spot = analyzer.spot_ltp
          expiry = analyzer.find_nearest_expiry

          if spot&.positive? && expiry
            legs = resolve_atm_legs(spot: spot, expiry: Date.parse(expiry))
            resubscribe_legs!(legs)

            chain_stale = false
            if Time.current - last_poll_at >= POLL_INTERVAL_SECONDS
              api_chain = analyzer.fetch_api_chain(expiry)
              chain_stale = api_chain.nil?
              legs = merge_chain_data(legs, api_chain)
              last_poll_at = Time.current
            end
            legs = merge_tick_data(legs)

            @mutex.synchronize do
              @snapshot = {
                index_key: @index_key, spot: spot, atm_strike: nearest_atm(spot, legs),
                expiry: expiry, legs: legs, chain_stale: chain_stale, updated_at: Time.current.iso8601
              }
            end

            ActionCable.server.broadcast("option_chain_#{@index_key}", snapshot)
          end
        rescue StandardError => e
          Rails.logger.error("[ChainWatchService:#{@index_key}] #{e.class} - #{e.message}")
        end

        sleep BROADCAST_INTERVAL_SECONDS
      end
    end

    def resubscribe_legs!(new_legs)
      new_keys = new_legs.map { |l| { segment: l[:segment], security_id: l[:security_id] } }
      old_keys = @subscribed_legs

      to_add = new_keys - old_keys
      to_remove = old_keys - new_keys

      Live::MarketFeedHub.instance.subscribe_many(to_add) if to_add.any?
      Live::MarketFeedHub.instance.unsubscribe_many(to_remove) if to_remove.any?

      @subscribed_legs = new_keys
    end

    def unsubscribe_current_legs!
      Live::MarketFeedHub.instance.unsubscribe_many(@subscribed_legs) if @subscribed_legs.any?
      @subscribed_legs = []
    end

    def nearest_atm(spot, legs)
      strikes = legs.map { |l| l[:strike] }.uniq
      return nil if strikes.empty?

      strikes.min_by { |s| (s - spot).abs }
    end

    def merge_tick_data(legs)
      legs.map do |leg|
        tick = Live::TickQuery.for_security(segment: leg[:segment], security_id: leg[:security_id])
        if tick&.ltp&.positive?
          leg.merge(
            ltp: tick.ltp.to_f, oi: tick.oi.to_i, oi_change: tick.oi_change.to_i,
            bid: tick.bid, ask: tick.ask, feed_stale: false
          )
        else
          leg.merge(feed_stale: true)
        end
      end
    end

    def merge_chain_data(legs, api_chain)
      return legs unless api_chain

      legs.map do |leg|
        strike_formats = [
          format('%<v>.6f', v: leg[:strike]), leg[:strike].to_s, leg[:strike].to_i.to_s
        ].uniq
        option_type_lower = leg[:type].to_s.downcase
        api_data = strike_formats.filter_map { |sf| api_chain.dig(sf, option_type_lower) }.first
        next leg unless api_data

        greeks = api_data['greeks'] || {}
        leg.merge(
          oi: api_data['oi']&.to_i || leg[:oi],
          iv: api_data['implied_volatility']&.to_f,
          delta: greeks['delta']&.to_f, gamma: greeks['gamma']&.to_f,
          theta: greeks['theta']&.to_f, vega: greeks['vega']&.to_f
        )
      end
    end

    def strike_increment_for(spot)
      return 25 unless spot&.positive?

      spot >= 50_000 ? 100 : (spot >= 10_000 ? 50 : 25)
    end
  end
end
