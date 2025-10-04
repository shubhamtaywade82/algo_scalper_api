# frozen_string_literal: true

require "bigdecimal"
require "time"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"

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
      data = resolve_data(payload)

      {
        order_no: fetch_value(data, :order_no, :order_id),
        exch_order_no: fetch_value(data, :exch_order_no, :exchange_order_no),
        status: fetch_value(data, :status, :order_status),
        quantity: safe_integer(fetch_value(data, :quantity)),
        traded_quantity: safe_integer(fetch_value(data, :traded_qty, :filled_quantity)),
        price: safe_decimal(fetch_value(data, :price)),
        avg_traded_price: safe_decimal(fetch_value(data, :avg_traded_price, :average_traded_price)),
        trigger_price: safe_decimal(fetch_value(data, :trigger_price)),
        transaction_type: fetch_value(data, :txn_type, :transaction_type),
        order_type: fetch_value(data, :order_type),
        product: fetch_value(data, :product, :product_name),
        validity: fetch_value(data, :validity),
        exchange: fetch_value(data, :exchange),
        segment: fetch_value(data, :segment),
        security_id: fetch_value(data, :security_id).to_s.presence,
        symbol: fetch_value(data, :symbol, :display_name),
        instrument_type: fetch_value(data, :instrument_type),
        order_date_time: safe_time(fetch_value(data, :order_date_time)),
        exchange_order_time: safe_time(fetch_value(data, :exch_order_time, :exchange_order_time)),
        last_updated_time: safe_time(fetch_value(data, :last_updated_time))
      }
    end

    def resolve_data(payload)
      candidates = [
        payload[:data], payload["data"], payload[:Data], payload["Data"]
      ].compact
      raw = candidates.find { |value| value.is_a?(Hash) } || payload
      raw.respond_to?(:deep_symbolize_keys) ? raw.deep_symbolize_keys : raw
    end

    def fetch_value(data, *keys)
      Array(keys).each do |key|
        candidates = build_candidates(key)
        candidates.each do |candidate|
          if data.respond_to?(candidate)
            value = data.public_send(candidate)
            return value unless value.nil?
          end
          next unless data.respond_to?(:[]) && data.key?(candidate)

          value = data[candidate]
          return value unless value.nil?
        end
      end

      nil
    end

    def build_candidates(key)
      str = key.to_s
      [
        key,
        str,
        str.underscore,
        str.camelize(:lower),
        str.camelize,
        str.upcase
      ].uniq
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
