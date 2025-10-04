# frozen_string_literal: true

require "json"
require "singleton"
require "sidekiq"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/hash/deep_transform_keys"
require "active_support/core_ext/string/inflections"

module Live
  class PositionStore
    include Singleton

    REDIS_KEY = "algo_scalper:positions:active"

    def refresh!
      active_positions = Array(fetch_active_positions)
      tracker_lookup = build_tracker_lookup

      active_keys = []
      grouped = Hash.new { |hash, key| hash[key] = [] }

      active_positions.each do |position|
        normalized = normalize(position, tracker_lookup)
        next unless normalized

        cache(normalized[:position_key], normalized[:payload])
        active_keys << normalized[:position_key]
        grouped[normalized[:security_id]] << normalized[:symbol_payload]
      end

      persist_closed_positions(active_keys)

      grouped
    rescue StandardError => e
      Rails.logger.error("Failed to refresh position store: #{e.class} - #{e.message}")
      positions_by_security
    end

    def positions_by_security
      cached_payloads = redis { |conn| conn.hvals(REDIS_KEY) } || []
      cached_payloads.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |json, grouped|
        data = decode(json)
        next if data.blank?

        grouped[data["security_id"].to_s] << symbolize(data)
      end
    end

    def remove(position_key)
      redis { |conn| conn.hdel(REDIS_KEY, position_key) }
    end

    private

    def fetch_active_positions
      Dhanhq.client.active_positions
    end

    def fetch_all_positions
      Dhanhq.client.positions
    rescue Dhanhq::Client::Error => e
      Rails.logger.warn("Unable to fetch full positions snapshot: #{e.message}")
      []
    end

    def build_tracker_lookup
      PositionTracker.active.pluck(:security_id, :order_no).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(security_id, order_no), map|
        map[security_id.to_s] << order_no
      end
    end

    def normalize(position, tracker_lookup)
      data = to_hash(position)
      return unless data.is_a?(Hash)

      with_strings = data.deep_stringify_keys
      security_id = fetch_value(with_strings, "security_id").to_s
      return if security_id.blank?

      product_type = fetch_value(with_strings, "product_type")
      position_type = fetch_value(with_strings, "position_type")
      position_key = build_position_key(security_id, product_type, position_type)
      return if position_key.blank?

      order_no = fetch_value(with_strings, "order_no").presence || tracker_lookup[security_id]&.first

      enriched = with_strings.merge(
        "security_id" => security_id,
        "product_type" => product_type,
        "position_type" => position_type,
        "position_key" => position_key,
        "order_no" => order_no
      )

      {
        position_key: position_key,
        security_id: security_id,
        payload: enriched,
        symbol_payload: symbolize(enriched)
      }
    end

    def persist_closed_positions(active_keys)
      existing_keys = redis { |conn| conn.hkeys(REDIS_KEY) } || []
      stale_keys = existing_keys - active_keys
      return if stale_keys.empty?

      closed_snapshots = lookup_closed_snapshots(stale_keys)

      stale_keys.each do |position_key|
        json = redis { |conn| conn.hget(REDIS_KEY, position_key) }
        redis { |conn| conn.hdel(REDIS_KEY, position_key) }
        next if json.blank?

        cached = decode(json)
        next if cached.blank?

        final_payload = closed_snapshots[position_key] || cached
        final_payload["order_no"] ||= cached["order_no"]
        Position.record_closed_position(final_payload, order_no: final_payload["order_no"])
      rescue StandardError => e
        Rails.logger.error("Failed to persist closed position #{position_key}: #{e.class} - #{e.message}")
      end
    end

    def lookup_closed_snapshots(keys)
      snapshots = Array(fetch_all_positions)
      snapshots.each_with_object({}) do |position, map|
        normalized = normalize(position, empty_tracker_lookup)
        next unless normalized
        next unless keys.include?(normalized[:position_key])

        map[normalized[:position_key]] = normalized[:payload]
      end
    rescue StandardError => e
      Rails.logger.warn("Unable to normalise closed positions: #{e.class} - #{e.message}")
      {}
    end

    def cache(position_key, payload)
      redis { |conn| conn.hset(REDIS_KEY, position_key, encode(payload)) }
    end

    def to_hash(position)
      if position.respond_to?(:to_h)
        position.to_h
      elsif position.respond_to?(:as_json)
        position.as_json
      elsif position.is_a?(Hash)
        position
      end
    end

    def fetch_value(hash, key)
      build_candidates(key).each do |candidate|
        return hash[candidate] if hash.key?(candidate)
      end
      nil
    end

    def empty_tracker_lookup
      Hash.new { |hash, key| hash[key] = [] }
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

    def encode(value)
      JSON.generate(value)
    end

    def decode(json)
      return if json.blank?

      JSON.parse(json)
    rescue JSON::ParserError
      nil
    end

    def symbolize(hash)
      hash.deep_transform_keys { |key| key.to_s.underscore.to_sym }
    end

    def redis
      Sidekiq.redis { |conn| yield(conn) }
    rescue StandardError => e
      Rails.logger.error("PositionStore redis call failed: #{e.class} - #{e.message}")
      nil
    end
  end
end
