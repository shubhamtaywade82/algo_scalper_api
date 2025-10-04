# frozen_string_literal: true

require "json"
require "singleton"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"

module Live
  class PositionStore
    include Singleton

    NAMESPACE = "algo_scalper:positions"

    def refresh_and_index
      active_positions = fetch_active_positions
      sync_active_positions(Array(active_positions))
      positions_by_security
    rescue StandardError => e
      Rails.logger.error("Failed to refresh position store: #{e.class} - #{e.message}")
      positions_by_security
    end

    def positions_by_security
      values = redis_call("HVALS", NAMESPACE) || []
      values.each_with_object({}) do |json, map|
        data = decode(json)
        next if data.blank?

        security_id = (data["security_id"] || data[:security_id]).to_s
        next if security_id.empty?

        map[security_id] ||= []
        map[security_id] << deep_symbolize(data)
      end
    end

    def remove(key)
      payload = redis_call("HGET", NAMESPACE, key)
      redis_call("HDEL", NAMESPACE, key)
      payload
    end

    private

    def fetch_active_positions
      Dhanhq.client.active_positions
    end

    def sync_active_positions(active_positions)
      active_keys = []

      active_positions.each do |position|
        normalized = normalize(position)
        next unless normalized

        active_keys << normalized[:key]
        redis_call("HSET", NAMESPACE, normalized[:key], encode(normalized[:data]))
      end

      persist_closed_positions(active_keys)
    end

    def normalize(position)
      data = to_hash(position)
      security_id = extract_string(data, :security_id)
      return if security_id.blank?

      key = build_key(data)
      return if key.blank?

      tracker_order_no = PositionTracker.active.find_by(security_id: security_id)&.order_no
      data["order_no"] ||= tracker_order_no if tracker_order_no

      {
        key: key,
        data: data.merge("position_key" => key, "security_id" => security_id)
      }
    end

    def persist_closed_positions(active_keys)
      existing_keys = redis_call("HKEYS", NAMESPACE) || []
      stale_keys = existing_keys - active_keys
      return if stale_keys.empty?

      stale_keys.each do |key|
        json = redis_call("HGET", NAMESPACE, key)
        redis_call("HDEL", NAMESPACE, key)
        next if json.blank?

        payload = decode(json)
        Position.record_closed_position(payload, order_no: payload["order_no"])
      rescue StandardError => e
        Rails.logger.error("Failed to persist closed position #{key}: #{e.class} - #{e.message}")
      end
    end

    def to_hash(position)
      if position.respond_to?(:to_h)
        position.to_h
      elsif position.respond_to?(:as_json)
        position.as_json
      else
        position
      end
    end

    def extract_string(data, key)
      value = data[key] || data[key.to_s] || data[key.to_s.camelize(:lower)]
      value.to_s
    rescue NoMethodError
      nil
    end

    def build_key(data)
      parts = [
        extract_string(data, :security_id),
        extract_string(data, :product_type),
        extract_string(data, :position_type)
      ].reject(&:blank?)

      parts.join(":")
    end

    def encode(value)
      JSON.generate(value)
    end

    def decode(value)
      return if value.nil?

      JSON.parse(value)
    rescue JSON::ParserError
      nil
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), memo|
          memo[k.to_s.underscore.to_sym] = deep_symbolize(v)
        end
      when Array
        value.map { |element| deep_symbolize(element) }
      else
        value
      end
    end

    def redis_call(command, *args)
      Sidekiq.redis do |conn|
        conn.call(command, *args)
      end
    rescue StandardError => e
      Rails.logger.error("PositionStore redis call failed for #{command}: #{e.class} - #{e.message}")
      nil
    end
  end
end
