# frozen_string_literal: true

require "bigdecimal"

module Equities
  PositionPlan = Struct.new(
    :quantity,
    :stop_price,
    :target_price,
    :risk_amount,
    :estimated_profit,
    keyword_init: true
  ) do
    def viable?
      quantity.to_i.positive?
    end
  end

  # Calculates position sizing for equities respecting balance, leverage and risk constraints.
  class PositionSizer
    DEFAULT_RISK_PERCENT = BigDecimal("0.01")
    PROFIT_CAP = BigDecimal("1000")
    MIN_PROFIT = BigDecimal("40")
    TARGET_MULTIPLIER = BigDecimal("2")

    def initialize(client: Dhanhq.client)
      @client = client
    end

    def build_plan(instrument:, signal:, balance: nil)
      balance ||= available_balance
      return PositionPlan.new(quantity: 0) if balance <= 0

      ltp = decimal(signal.ltp)
      stop_distance = decimal(signal.stop_distance)
      return PositionPlan.new(quantity: 0) if stop_distance <= 0

      max_risk = balance * DEFAULT_RISK_PERCENT
      risk_per_share = stop_distance
      base_qty = (max_risk / risk_per_share).floor
      return PositionPlan.new(quantity: 0) if base_qty <= 0

      leverage = leverage_for(instrument)
      quantity = (base_qty * leverage).floor
      return PositionPlan.new(quantity: 0) if quantity <= 0

      target_distance = stop_distance * TARGET_MULTIPLIER
      stop_price = signal.direction == :long ? ltp - stop_distance : ltp + stop_distance
      target_price = signal.direction == :long ? ltp + target_distance : ltp - target_distance

      estimated_profit = target_distance * quantity
      if estimated_profit > PROFIT_CAP
        quantity = (PROFIT_CAP / target_distance).floor
      elsif estimated_profit < MIN_PROFIT
        return PositionPlan.new(quantity: 0)
      end

      return PositionPlan.new(quantity: 0) if quantity <= 0

      quantity = [ quantity, 1 ].max
      estimated_profit = target_distance * quantity
      risk_amount = risk_per_share * quantity

      PositionPlan.new(
        quantity: quantity,
        stop_price: stop_price,
        target_price: target_price,
        risk_amount: risk_amount,
        estimated_profit: estimated_profit
      )
    end

    private

    def available_balance
      funds = @client.funds
      if funds.respond_to?(:available_balance)
        decimal(funds.available_balance)
      elsif funds.respond_to?(:cash_available)
        decimal(funds.cash_available)
      elsif funds.is_a?(Hash)
        decimal(funds[:available_balance] || funds[:cash_available])
      else
        BigDecimal("0")
      end
    rescue StandardError
      BigDecimal("0")
    end

    def leverage_for(instrument)
      leverage = instrument.mtf_leverage || instrument.buy_bo_min_margin_per
      leverage = leverage.to_f
      leverage.positive? ? leverage : 1
    end

    def decimal(value)
      BigDecimal(value.to_s)
    rescue ArgumentError
      BigDecimal("0")
    end
  end
end
