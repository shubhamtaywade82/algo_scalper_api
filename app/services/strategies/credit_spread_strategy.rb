# frozen_string_literal: true

module Strategies
  # Constructs credit spread legs with hedge-first ordering (buy hedge = 1, sell short = 2).
  # Supports Bull Put Spreads (bullish/ranging) and Bear Call Spreads (bearish/ranging).
  class CreditSpreadStrategy
    attr_reader :index_key, :strategy_type, :expiry, :quantity

    def initialize(index_key:, strategy_type:, expiry: nil, quantity: 1)
      @index_key = index_key.to_s.upcase
      @strategy_type = strategy_type.to_sym
      @expiry = expiry
      @quantity = quantity
    end

    def build_legs(short_leg_candidate:, long_leg_candidate:)
      case strategy_type
      when :bull_put_spread
        build_bull_put_spread(short_leg_candidate, long_leg_candidate)
      when :bear_call_spread
        build_bear_call_spread(short_leg_candidate, long_leg_candidate)
      else
        raise ArgumentError, "Unsupported credit spread strategy: #{strategy_type}"
      end
    end

    private

    # Buy lower strike Put (hedge), Sell higher strike Put (premium)
    def build_bull_put_spread(short_leg, long_leg)
      [
        {
          leg_order: 1,
          type: :long_put,
          action: 'buy',
          security_id: long_leg[:security_id],
          segment: long_leg[:exchange_segment] || long_leg[:segment] || 'NSE_FNO',
          strike: long_leg[:strike],
          option_type: 'PE',
          quantity: quantity,
          expiry: expiry || long_leg[:expiry_date]
        },
        {
          leg_order: 2,
          type: :short_put,
          action: 'sell',
          security_id: short_leg[:security_id],
          segment: short_leg[:exchange_segment] || short_leg[:segment] || 'NSE_FNO',
          strike: short_leg[:strike],
          option_type: 'PE',
          quantity: quantity,
          expiry: expiry || short_leg[:expiry_date]
        }
      ]
    end

    # Buy higher strike Call (hedge), Sell lower strike Call (premium)
    def build_bear_call_spread(short_leg, long_leg)
      [
        {
          leg_order: 1,
          type: :long_call,
          action: 'buy',
          security_id: long_leg[:security_id],
          segment: long_leg[:exchange_segment] || long_leg[:segment] || 'NSE_FNO',
          strike: long_leg[:strike],
          option_type: 'CE',
          quantity: quantity,
          expiry: expiry || long_leg[:expiry_date]
        },
        {
          leg_order: 2,
          type: :short_call,
          action: 'sell',
          security_id: short_leg[:security_id],
          segment: short_leg[:exchange_segment] || short_leg[:segment] || 'NSE_FNO',
          strike: short_leg[:strike],
          option_type: 'CE',
          quantity: quantity,
          expiry: expiry || short_leg[:expiry_date]
        }
      ]
    end
  end
end
