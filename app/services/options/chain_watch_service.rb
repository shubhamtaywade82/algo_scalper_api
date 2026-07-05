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
      @snapshot = { index_key: @index_key, spot: nil, atm_strike: nil, expiry: nil, legs: [], chain_stale: true, updated_at: nil }
      @subscribed_legs = []
    end

    def running?
      @running
    end

    def snapshot
      @mutex.synchronize { @snapshot.dup }
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

    def strike_increment_for(spot)
      return 25 unless spot&.positive?

      spot >= 50_000 ? 100 : (spot >= 10_000 ? 50 : 25)
    end
  end
end
