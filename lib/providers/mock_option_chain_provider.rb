# frozen_string_literal: true

module Providers
  class MockOptionChainProvider
    def initialize(spot_price: 20_000, strike_interval: 50)
      @spot_price = spot_price
      @strike_interval = strike_interval
    end

    def underlying_spot(_index)
      @spot_price
    end

    def option_chain(_index)
      atm_strike = (@spot_price / @strike_interval).round * @strike_interval
      strikes = generate_strikes(atm_strike)

      strikes.map do |strike|
        {
          strike: strike,
          type: strike >= atm_strike ? 'CE' : 'PE',
          ltp: calculate_mock_ltp(strike, atm_strike),
          bid: calculate_mock_bid(strike, atm_strike),
          ask: calculate_mock_ask(strike, atm_strike),
          oi: rand(50_000..1_000_000),
          iv: rand(15.0..35.0).round(2),
          volume: rand(1000..50_000),
          prev_close: calculate_mock_ltp(strike, atm_strike) * (0.95 + rand * 0.1)
        }
      end
    end

    private

    def generate_strikes(atm_strike)
      strikes = []
      (-3..3).each do |offset|
        strikes << atm_strike + (offset * @strike_interval)
      end
      strikes.select(&:positive?).sort
    end

    def calculate_mock_ltp(strike, atm_strike)
      distance = (strike - atm_strike).abs
      base_price = 100.0
      time_value = 50.0
      intrinsic = [atm_strike - strike, 0].max * 0.01
      (base_price + time_value - (distance * 0.5) + intrinsic).round(2)
    end

    def calculate_mock_bid(strike, atm_strike)
      ltp = calculate_mock_ltp(strike, atm_strike)
      (ltp * 0.995).round(2)
    end

    def calculate_mock_ask(strike, atm_strike)
      ltp = calculate_mock_ltp(strike, atm_strike)
      (ltp * 1.005).round(2)
    end
  end
end

