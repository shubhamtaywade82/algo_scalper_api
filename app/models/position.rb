# frozen_string_literal: true

require "bigdecimal"
require "time"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/hash/deep_dup"
require "active_support/core_ext/hash/transform_keys"
require "active_support/core_ext/string/inflections"

class Position < ApplicationRecord
  validates :position_key, presence: true, uniqueness: true
  validates :security_id, presence: true
  validates :closed_at, presence: true

  class << self
    def record_closed_position(payload, order_no: nil)
      normalized = normalize_payload(payload, order_no: order_no)
      return unless normalized

      record = find_or_initialize_by(position_key: normalized[:position_key])
      record.assign_attributes(normalized.except(:position_key))
      record.save!
      record
    end

    private

    def normalize_payload(payload, order_no: nil)
      data = to_hash(payload)
      return unless data

      with_strings = data.deep_stringify_keys
      security_id = fetch_value(with_strings, "security_id")
      return if security_id.blank?

      product_type = fetch_value(with_strings, "product_type")
      position_type = fetch_value(with_strings, "position_type")
      position_key = build_position_key(security_id, product_type, position_type)
      closed_at = parse_time(fetch_value(with_strings, "closed_at") || fetch_value(with_strings, "last_updated_time")) || Time.current

      {
        position_key: position_key,
        order_no: order_no.presence || fetch_value(with_strings, "order_no"),
        security_id: security_id,
        product_type: product_type,
        position_type: position_type,
        realized_profit: to_decimal(fetch_value(with_strings, "realized_profit")),
        unrealized_profit: to_decimal(fetch_value(with_strings, "unrealized_profit")),
        closed_at: closed_at,
        raw_payload: with_strings
      }
    end

    def to_hash(payload)
      if payload.respond_to?(:to_h)
        payload.to_h
      elsif payload.respond_to?(:as_json)
        payload.as_json
      elsif payload.is_a?(Hash)
        payload
      end
    end

    def fetch_value(hash, key)
      candidates = build_candidates(key)
      candidates.each do |candidate|
        return hash[candidate] if hash.key?(candidate)
      end
      nil
    end

    def build_candidates(key)
      str = key.to_s
      [
        str,
        str.underscore,
        str.camelize(:lower),
        str.camelize,
        str.upcase
      ].uniq
    end

    def build_position_key(security_id, product_type, position_type)
      [security_id, product_type, position_type].compact.join(":")
    end

    def to_decimal(value)
      return if value.nil?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_time(value)
      return if value.blank?

      (Time.zone || Time).parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
