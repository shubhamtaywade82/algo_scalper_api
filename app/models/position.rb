# frozen_string_literal: true

require "bigdecimal"
require "date"
require "time"

class Position < ApplicationRecord
  validates :position_key, presence: true, uniqueness: true
  validates :security_id, presence: true

  class << self
    def record_closed_position(payload, order_no: nil)
      return if payload.blank?

      attributes = extract_attributes(payload)
      attributes[:order_no] ||= order_no
      attributes[:closed_at] ||= Time.current
      attributes[:raw_payload] = payload

      position = find_or_initialize_by(position_key: attributes[:position_key])
      position.assign_attributes(attributes)
      position.save!
      position
    end

    private

    def extract_attributes(payload)
      data =
        if payload.respond_to?(:deep_symbolize_keys)
          payload.deep_symbolize_keys
        else
          payload
        end

      {
        position_key: data[:position_key] || build_position_key(data),
        order_no: data[:order_no],
        dhan_client_id: data[:dhan_client_id] || data[:dhan_clientID],
        trading_symbol: data[:trading_symbol],
        security_id: (data[:security_id] || data[:securityId]).to_s,
        position_type: data[:position_type] || data[:positionType],
        exchange_segment: data[:exchange_segment] || data[:exchangeSegment],
        product_type: data[:product_type] || data[:productType],
        buy_avg: to_decimal(data[:buy_avg] || data[:buyAvg]),
        buy_qty: to_integer(data[:buy_qty] || data[:buyQty]),
        cost_price: to_decimal(data[:cost_price]),
        sell_avg: to_decimal(data[:sell_avg] || data[:sellAvg]),
        sell_qty: to_integer(data[:sell_qty] || data[:sellQty]),
        net_qty: to_integer(data[:net_qty] || data[:netQty]),
        realized_profit: to_decimal(data[:realized_profit] || data[:realizedProfit]),
        unrealized_profit: to_decimal(data[:unrealized_profit] || data[:unrealizedProfit]),
        rbi_reference_rate: to_decimal(data[:rbi_reference_rate] || data[:rbiReferenceRate]),
        multiplier: to_integer(data[:multiplier]),
        carry_forward_buy_qty: to_integer(data[:carry_forward_buy_qty] || data[:carryForwardBuyQty]),
        carry_forward_sell_qty: to_integer(data[:carry_forward_sell_qty] || data[:carryForwardSellQty]),
        carry_forward_buy_value: to_decimal(data[:carry_forward_buy_value] || data[:carryForwardBuyValue]),
        carry_forward_sell_value: to_decimal(data[:carry_forward_sell_value] || data[:carryForwardSellValue]),
        day_buy_qty: to_integer(data[:day_buy_qty] || data[:dayBuyQty]),
        day_sell_qty: to_integer(data[:day_sell_qty] || data[:daySellQty]),
        day_buy_value: to_decimal(data[:day_buy_value] || data[:dayBuyValue]),
        day_sell_value: to_decimal(data[:day_sell_value] || data[:daySellValue]),
        drv_expiry_date: parse_date(data[:drv_expiry_date] || data[:drvExpiryDate]),
        drv_option_type: data[:drv_option_type] || data[:drvOptionType],
        drv_strike_price: to_decimal(data[:drv_strike_price] || data[:drvStrikePrice]),
        cross_currency: to_boolean(data[:cross_currency] || data[:crossCurrency]),
        closed_at: parse_time(data[:closed_at] || data[:closedAt] || data[:last_updated_time] || data[:lastUpdatedTime])
      }
    end

    def build_position_key(data)
      security_id = (data[:security_id] || data[:securityId]).to_s
      product_type = data[:product_type] || data[:productType]
      position_type = data[:position_type] || data[:positionType]

      [security_id, product_type, position_type].compact.join(":")
    end

    def to_decimal(value)
      return if value.nil?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def to_integer(value)
      return if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_date(value)
      return if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def to_boolean(value)
      case value
      when true, false
        value
      when String
        value.casecmp("true").zero? || value == "1"
      when Numeric
        !value.to_i.zero?
      else
        nil
      end
    end

    def parse_time(value)
      return if value.blank?

      if Time.zone
        Time.zone.parse(value.to_s)
      else
        Time.parse(value.to_s)
      end
    rescue ArgumentError
      nil
    end
  end
end
