# frozen_string_literal: true

require 'active_support/core_ext/hash'
require 'active_support/core_ext/object/blank'

module Signal
  module Engines
    class BaseEngine
      STATE_MUTEX = Mutex.new
      STATE = Hash.new { |hash, key| hash[key] = {} }

      def initialize(index:, config:, option_candidate:, tick_cache: Live::RedisTickCache.instance)
        @index = normalize_index(index)
        @config = config || {}
        @option_candidate = option_candidate&.deep_symbolize_keys
        @tick_cache = tick_cache
      end

      protected

      def tick_of(sid, segment: option_segment)
        return unless sid && segment

        @tick_cache.fetch_tick(segment, sid)
      end

      def option_tick
        sid = option_security_id
        return unless sid

        tick_of(sid)
      end

      def option_security_id
        @option_candidate&.[](:security_id) || @index.dig(:options, :atm_sid)
      end

      def option_segment
        @option_candidate&.[](:segment) || @index[:segment]
      end

      def create_signal(reason:, meta: {})
        sid = option_security_id
        return unless sid

        multiplier = strategy_threshold(:multiplier, 1).to_i
        multiplier = 1 unless multiplier.positive?

        {
          segment: option_segment,
          security_id: sid,
          reason: reason,
          meta: {
            index: @index[:key],
            candidate_symbol: @option_candidate&.[](:symbol),
            strategy: self.class.name,
            lot_size: option_lot_size,
            multiplier: multiplier
          }.merge(meta).compact
        }
      end

      def state_get(key, default = nil)
        STATE_MUTEX.synchronize { STATE[state_key][key] } || default
      end

      def state_set(key, value)
        STATE_MUTEX.synchronize { STATE[state_key][key] = value }
      end

      def strategy_threshold(key, default = nil)
        @config.fetch(key, default)
      end

      def option_lot_size
        lot = @option_candidate&.[](:lot_size) ||
              @index[:lot_size] ||
              @index[:lot]
        lot = lot.to_i
        lot.positive? ? lot : 1
      end

      def effective_lot_size(multiplier_key = :lot_multiplier, default_multiplier = 1)
        multiplier = strategy_threshold(multiplier_key, default_multiplier).to_i
        multiplier = default_multiplier unless multiplier.positive?
        option_lot_size * multiplier
      end

      private

      def normalize_index(index)
        return index.deep_symbolize_keys if index.respond_to?(:deep_symbolize_keys)

        Array(index).transform_keys(&:to_sym)
      end

      def state_key
        "#{@index[:key]}::#{self.class.name}"
      end
    end
  end
end
