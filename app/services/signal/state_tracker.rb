# frozen_string_literal: true

module Signal
  class StateTracker
    CACHE_PREFIX = "signal:state"

    class << self
      def record(index_key:, direction:, candle_timestamp:, config: {})
        scaling_cfg = config.fetch(:scaling, {})
        return default_response(direction) unless scaling_cfg.fetch(:enabled, false)

        key = cache_key(index_key)
        state = Rails.cache.read(key) || {}
        last_direction = state[:direction]&.to_sym
        last_timestamp = normalized_timestamp(state[:last_candle_timestamp])
        current_timestamp = normalized_timestamp(candle_timestamp)

        same_direction = last_direction == direction
        new_candle = current_timestamp.present? && current_timestamp != last_timestamp

        count =
          if same_direction && new_candle
            state[:count].to_i + 1
          elsif same_direction
            [ state[:count].to_i, 1 ].max
          else
            1
          end

        updated_state = {
          direction: direction,
          count: count,
          last_candle_timestamp: current_timestamp,
          last_seen_at: Time.current
        }

        ttl = [ scaling_cfg.fetch(:decay_seconds, 900).to_i, 0 ].max
        Rails.cache.write(key, updated_state, expires_in: ttl)

        multiplier = [
          [count, 1].max,
          [scaling_cfg.fetch(:max_multiplier, 1).to_i, 1].max
        ].min

        {
          count: count,
          multiplier: multiplier
        }
      end

      def reset(index_key)
        Rails.cache.delete(cache_key(index_key))
      end

      private

      def cache_key(index_key)
        "#{CACHE_PREFIX}:#{index_key}"
      end

      def normalized_timestamp(value)
        return if value.blank?

        case value
        when Time
          value.to_i
        when DateTime
          value.to_time.to_i
        else
          value.to_i
        end
      end

      def default_response(direction)
        {
          count: direction.nil? || direction == :avoid ? 0 : 1,
          multiplier: 1
        }
      end
    end
  end
end
