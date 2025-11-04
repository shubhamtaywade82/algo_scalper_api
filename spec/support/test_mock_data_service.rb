# frozen_string_literal: true

module Live
  class TestMockDataService
    include Singleton

    def initialize
      @running = false
      @thread = nil
      @tick_data = {}
    end

    def start!
      return if @running

      @running = true
      # Rails.logger.info('[TestMockData] Starting test mock data service')

      # Generate initial test data
      generate_test_data
    end

    def stop!
      @running = false
      @thread&.join
      # Rails.logger.info('[TestMockData] Test mock data service stopped')
    end

    def running?
      @running
    end

    # Manually inject tick data for testing
    def inject_tick(tick_data)
      tick = normalize_tick(tick_data)
      Live::TickCache.put(tick)

      # Trigger callbacks if market feed hub is running
      Live::MarketFeedHub.instance.send(:handle_tick, tick) if Live::MarketFeedHub.instance.running?

      tick
    end

    # Generate a series of ticks for testing
    def generate_tick_series(base_price, count: 10, interval: 0.1)
      ticks = []
      count.times do |i|
        price = base_price + ((rand - 0.5) * base_price * 0.01) # ±0.5% variation
        tick = {
          segment: 'NSE_FNO',
          security_id: '12345',
          ltp: price.round(2),
          kind: :quote,
          ts: Time.current.to_i + i
        }
        ticks << inject_tick(tick)
        sleep(interval) if interval > 0
      end
      ticks
    end

    # Generate mock option chain data
    def generate_option_ticks(underlying_price, strike_prices, option_type: :call)
      ticks = []
      strike_prices.each do |strike|
        # Simple option pricing model for testing
        intrinsic_value = if option_type == :call
                            [underlying_price - strike,
                             0].max
                          else
                            [strike - underlying_price, 0].max
                          end
        time_value = rand(1.0..5.0)
        option_price = intrinsic_value + time_value

        tick = {
          segment: 'NSE_FNO',
          security_id: "#{strike}#{option_type == :call ? 'CE' : 'PE'}",
          ltp: option_price.round(2),
          kind: :quote,
          ts: Time.current.to_i
        }
        ticks << inject_tick(tick)
      end
      ticks
    end

    private

    def generate_test_data
      # Generate test data for common instruments
      test_instruments = [
        { segment: 'NSE_FNO', security_id: '12345', name: 'NIFTY', base_price: 25_200 },
        { segment: 'NSE_FNO', security_id: '67890', name: 'BANKNIFTY', base_price: 56_500 },
        { segment: 'IDX_I', security_id: '13', name: 'NIFTY_IDX', base_price: 25_200 },
        { segment: 'IDX_I', security_id: '25', name: 'BANKNIFTY_IDX', base_price: 56_500 }
      ]

      test_instruments.each do |instrument|
        tick = {
          segment: instrument[:segment],
          security_id: instrument[:security_id],
          ltp: instrument[:base_price] + rand(-100..100),
          kind: :quote,
          ts: Time.current.to_i
        }
        @tick_data["#{instrument[:segment]}:#{instrument[:security_id]}"] = tick
      end
    end

    def normalize_tick(tick_data)
      {
        segment: tick_data[:segment] || tick_data['segment'],
        security_id: tick_data[:security_id] || tick_data['security_id'],
        ltp: tick_data[:ltp] || tick_data['ltp'],
        kind: tick_data[:kind] || tick_data['kind'] || :quote,
        ts: tick_data[:ts] || tick_data['ts'] || Time.current.to_i
      }
    end
  end
end
