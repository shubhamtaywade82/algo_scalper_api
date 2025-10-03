# frozen_string_literal: true

require "concurrent/map"

module Live
  class TickCache
    MAP = Concurrent::Map.new

    class << self
      def put(tick)
        MAP[key(tick[:segment], tick[:security_id])] = tick
      end

      def get(segment, security_id)
        MAP[key(segment, security_id)]
      end

      def ltp(segment, security_id)
        get(segment, security_id)&.dig(:ltp)
      end

      def clear
        MAP.clear
      end

      private

      def key(segment, security_id)
        "#{segment}:#{security_id}"
      end
    end
  end
end
