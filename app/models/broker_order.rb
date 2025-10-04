# frozen_string_literal: true

require "bigdecimal"
require "time"

class BrokerOrder < ApplicationRecord
  validates :order_no, presence: true, uniqueness: true
  validates :status, presence: true

  class << self
    def upsert_from_payload(payload)
      return unless payload.is_a?(Hash)

      attributes = extract_attributes(payload)
      return if attributes[:order_no].blank? || attributes[:status].blank?

      record = find_or_initialize_by(order_no: attributes[:order_no])
      record.assign_attributes(attributes.except(:order_no))
      record.raw_payload = deep_stringify(payload)
      record.save!
      record
    end

    private

    def extract_attributes(payload)
      data = payload[:data].is_a?(Hash) ? payload[:data] : payload

      {
        order_no: data[:order_no] || data[:order_id],
        exch_order_no: data[:exch_order_no],
        status: data[:status] || data[:order_status],
        quantity: safe_integer(data[:quantity]),
        traded_quantity: safe_integer(data[:traded_qty] || data[:filled_quantity]),
        price: safe_decimal(data[:price]),
        avg_traded_price: safe_decimal(data[:avg_traded_price] || data[:average_traded_price]),
        trigger_price: safe_decimal(data[:trigger_price]),
        transaction_type: data[:txn_type] || data[:transaction_type],
        order_type: data[:order_type],
        product: data[:product] || data[:product_name],
        validity: data[:validity],
        exchange: data[:exchange],
        segment: data[:segment],
        security_id: data[:security_id]&.to_s,
        symbol: data[:symbol] || data[:display_name],
        instrument_type: data[:instrument_type],
        order_date_time: safe_time(data[:order_date_time]),
        exchange_order_time: safe_time(data[:exch_order_time] || data[:exchange_order_time]),
        last_updated_time: safe_time(data[:last_updated_time])
      }
    end

    def safe_decimal(value)
      return if value.nil?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def safe_integer(value)
      return if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    def safe_time(value)
      return if value.blank?

      zone = Time.zone
      parser = zone || Time
      parser.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def deep_stringify(value)
      return value unless value.respond_to?(:deep_stringify_keys)

      value.deep_stringify_keys
    end
  end
end
